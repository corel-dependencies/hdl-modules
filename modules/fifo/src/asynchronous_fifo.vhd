-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the hdl_modules project.
-- https://hdl-modules.com
-- https://gitlab.com/tsfpga/hdl_modules
-- -------------------------------------------------------------------------------------------------
-- Asynchronous (two clocks) First In First Out (FIFO) data buffering stage with AXI-Stream-like
-- handshaking interface.
-- Supports ``last``, packet mode and ``drop_packet`` just like the
-- :ref:`synchronous FIFO <fifo.fifo>`.
-- The implementation is quite opitmized with very low resource utilization when extra features
-- are not enabled.
--
-- .. note::
--   This entity has a scoped constraint file that must be used, it further instantiates
--   :ref:`resync.resync_counter` which also has a constraint file.
--
-- .. warning::
--   In case ``enable_output_register`` is set, the implementation doesn't keep track of
--   the exact level on the write side. When there is no word in the output register,
--   e.g when the fifo is empty the write_level reported will be one higher than the real level.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library common;
use common.attribute_pkg.all;
use common.types_pkg.all;

library math;
use math.math_pkg.all;

library resync;


entity asynchronous_fifo is
  generic (
    width : positive;
    depth : positive;
    -- Changing these levels from default value will increase logic footprint
    almost_full_level : integer range 0 to depth := depth;
    almost_empty_level : integer range 0 to depth := 0;
    -- Set to true in order to use 'read_last' and 'write_last'
    enable_last : boolean := false;
    -- If enabled, 'read_valid' will not be asserted until a full packet is available in
    -- FIFO. I.e. when 'write_last' has been received.
    enable_packet_mode : boolean := false;
    -- Set to true in order to use the 'drop_packet' port. Must set 'enable_packet_mode' as
    -- well to use this.
    enable_drop_packet : boolean := false;
    -- Use an extra output register. This will be integrated in the memory if block RAM is used.
    -- Increases latency but improves timing.
    -- When enabled, the output register is included in the 'depth',
    -- meaning that the RAM depth is 'depth - 1'.
    enable_output_register : boolean := false;
    -- Select what FPGA primitives will be used to implement the FIFO memory.
    ram_type : ram_style_t := ram_style_auto
  );
  port (
    -- Read data interface
    clk_read : in std_logic;
    read_ready : in  std_logic;
    -- '1' if FIFO is not empty
    read_valid : out std_logic := '0';
    read_data : out std_logic_vector(width - 1 downto 0) := (others => '0');
    -- Must set 'enable_last' generic in order to use this
    read_last : out std_logic := '0';

    -- Status signals on the read side. Updated one clock cycle after read transactions.
    -- Updated "a while" after write transactions (not deterministic).
    --
    -- Note that this port will be CONSTANTLY ZERO if the 'enable_packet_mode' generic is set
    -- to true. This is since a glitch-free value can not be guaranteed in this mode.
    read_level : out integer range 0 to depth := 0;
    -- '1' if there are 'almost_empty_level' or fewer words available to read.
    --
    -- Note that this port will be CONSTANTLY ONE if the 'enable_packet_mode' generic is set
    -- to true, and 'almost_empty_level' has a non-default value.
    -- This is since a glitch-free value of 'read_level' can not be guaranteed in this mode.
    read_almost_empty : out std_logic := '1';

    --# {{}}
    -- Write data interface
    clk_write : in std_logic;
    -- '1' if FIFO is not full
    write_ready : out std_logic := '1';
    write_valid : in  std_logic;
    write_data  : in  std_logic_vector(width - 1 downto 0);
    -- Must set 'enable_last' generic in order to use this
    write_last : in std_logic := '0';

    -- Status signals on the write side. Updated one clock cycle after write transactions.
    -- Updated "a while" after read transactions (not deterministic).
    -- In case the enable_output_register is set, this value will never go below 1
    write_level : out integer range 0 to depth := to_int(enable_output_register);
    -- '1' if there are 'almost_full_level' or more words available in the FIFO
    write_almost_full : out std_logic := '0';

    -- Drop the current packet (all words that have been writen since the previous 'write_last').
    -- Must set 'enable_drop_packet' generic in order to use this.
    drop_packet : in std_logic := '0'
  );
end entity;

architecture a of asynchronous_fifo is

  constant memory_depth : positive := depth - to_int(enable_output_register);

  -- Need one extra bit in the addresses to be able to make the distinction if the FIFO
  -- is full or empty (where the addresses would otherwise be equal).
  subtype fifo_addr_t is unsigned(num_bits_needed(2 * memory_depth - 1) - 1 downto 0);
  signal read_addr_next, write_addr : fifo_addr_t := (others => '0');

  -- The counter for number of lasts in the FIFO (used by packet mode) also needs one extra bit,
  -- to cover the case when the whole FIFO depth has been written with lasts, and the
  -- extra word that be occupied in the output register if enable_output_register is used.
  signal num_lasts_written : fifo_addr_t := (others => '0');

  -- The part of the address that actually goes to the BRAM address port
  subtype bram_addr_range is integer range num_bits_needed(memory_depth - 1) - 1 downto 0;

  signal read_ready_ram, read_valid_ram, read_last_ram : std_logic := '0';
  signal read_data_ram : std_logic_vector(width - 1 downto 0) := (others => '0');
  signal word_in_output_register : integer range 0 to 1 := 0;

begin

  assert is_power_of_two(depth - to_int(enable_output_register))
    report "RAM depth must be a power of two." severity failure;

  assert enable_last or (not enable_packet_mode)
    report "Must set enable_last for packet mode" severity failure;
  assert enable_packet_mode or (not enable_drop_packet)
    report "Must set enable_packet_mode for drop packet support" severity failure;


  assign_almost_full : if almost_full_level = depth generate
    write_almost_full <= not write_ready;
  else generate
    write_almost_full <= to_sl(write_level > almost_full_level - 1);
  end generate;

  assign_almost_empty : if almost_empty_level = 0 generate
    read_almost_empty <= not read_valid;
  else generate
    -- Note that read_level will always be zero if drop_packet support is enabled, making this
    -- signal always '1' in that mode.
    read_almost_empty <= to_sl(read_level < almost_empty_level + 1);
  end generate;


  ------------------------------------------------------------------------------
  write_block : block
    signal write_addr_next, write_addr_next_if_not_drop, write_addr_start_of_packet :
      fifo_addr_t := (others => '0');
    signal read_addr_resync : fifo_addr_t := (others => '0');
  begin

    ------------------------------------------------------------------------------
    write_status : process
    begin
      wait until rising_edge(clk_write);

      if enable_drop_packet then
        num_lasts_written <= num_lasts_written
          + to_int(write_ready and write_valid and write_last and not drop_packet);
      else
        num_lasts_written <= num_lasts_written + to_int(write_ready and write_valid and write_last);
      end if;

      -- Note that write_ready looks at the next write address that will be used if there is
      -- no packet drop. This is done to ease the timing of write_ready which is
      -- often critical. There is a functional difference only in the special case when the FIFO
      -- goes full in the same cycle as drop_packet is sent. In that case, write_ready will be low
      -- for one cycle and then go high the next.
      write_ready <= to_sl(
        read_addr_resync(bram_addr_range) /= write_addr_next_if_not_drop(bram_addr_range)
        or read_addr_resync(read_addr_resync'high) =  write_addr_next_if_not_drop(write_addr_next'high));

      -- Note that this potential update of write_addr_next does not affect write_ready,
      -- assigned above. This is done to save logic and ease the timing of write_ready which is
      -- often critical. There is a functional difference only in the special case when the FIFO
      -- goes full in the same cycle as drop_packet is sent. In that case, write_ready will be low
      -- for one cycle and then go high the next.
      if enable_drop_packet then
        if (not drop_packet) and write_ready and write_valid and write_last then
          write_addr_start_of_packet <= write_addr_next;
        end if;
      end if;

      -- These signals however must have the updated value.
      write_addr <= write_addr_next;
      -- The write_level must never be less than the actual number of words stored in the fifo,
      -- as that could cause the user to write too many words.
      -- In case the output register is used, it is hard to keep track of the exact level in a
      -- safe way, so instead we always add one to the write_level in that case.
      write_level <= to_integer(write_addr_next - read_addr_resync) mod (2 * memory_depth) + to_int(enable_output_register);
    end process;

    write_addr_next_if_not_drop <= write_addr + to_int(write_ready and write_valid);
    write_addr_next <=
      write_addr_start_of_packet when enable_drop_packet and drop_packet = '1'
      else write_addr_next_if_not_drop;


    ------------------------------------------------------------------------------
    resync_read_addr : entity resync.resync_counter
      generic map (
        width => read_addr_next'length
      )
      port map (
        clk_in      => clk_read,
        counter_in  => read_addr_next,
        clk_out     => clk_write,
        counter_out => read_addr_resync
      );

  end block;


  ------------------------------------------------------------------------------
  read_block : block
    signal write_addr_resync, read_addr : fifo_addr_t := (others => '0');
    signal num_lasts_read, num_lasts_written_resync : fifo_addr_t := (others => '0');
  begin

    ------------------------------------------------------------------------------
    read_status : process
      variable read_level_next : integer range 0 to depth;
      variable num_lasts_read_next : fifo_addr_t := (others => '0');
      variable word_in_output_register_next : integer range 0 to 1 := 0;
    begin
      wait until rising_edge(clk_read);

      read_addr <= read_addr_next;

      -- If drop_packet support is enabled, the write_addr can make jumps that are greater
      -- than +/- 1. This means that the resynced counter can have glitches, since it is possible
      -- that the counter value is sampled just as more than one bit are changing.
      -- This is an issue despite the value being gray-coded and the bus_skew constraint
      -- being present.
      --
      -- Since we can not guarantee a glitch-free read_level value in this mode, we simply do not
      -- assign the counter.
      if not enable_drop_packet then
        read_level_next :=
          to_integer(write_addr_resync - read_addr_next) mod (2 * memory_depth);

        -- Keep track of if there is a word in the output register, if it is included
        if enable_output_register then
          word_in_output_register_next :=
            word_in_output_register
            -- One word is added on handshake on the input
            + to_int(read_ready_ram and read_valid_ram)
            -- And one word is removed on handshake on the output
            - to_int(read_ready and read_valid);
            word_in_output_register <= word_in_output_register_next;
        end if;

        read_level <= read_level_next + word_in_output_register_next;
      end if;

      if enable_packet_mode then
        if enable_output_register and not enable_drop_packet then
          -- When the output register is used, there is one extra cycle latency when reading.
          -- That means that the last 'last' bit may be on its way to the output register right now,
          -- and that there therefore isn't any 'last' bit left in the RAM.
          -- Therefore we only read from RAM if it is not empty
          -- We do _not_ want to look at the read_last_ram signal here, as it is part of the read data,
          -- and using it would make it impossible to use the RAM output_register.
          -- Note: the level counter is not present if enable_drop_packet is activated, so in that case
          --       we take the "else" branch, which is functionally correct but will not utilize the
          --       RAM output register.
          num_lasts_read_next := num_lasts_read + to_int(read_ready and read_valid and read_last);
          read_valid_ram <= to_sl(num_lasts_read /= num_lasts_written_resync and read_level_next /= 0);
        else
          num_lasts_read_next := num_lasts_read + to_int(read_ready_ram and read_valid_ram and read_last_ram);
          read_valid_ram <= to_sl(num_lasts_read_next /= num_lasts_written_resync);
        end if;

      else
        read_valid_ram <= to_sl(read_level_next /= 0);
      end if;

      num_lasts_read <= num_lasts_read_next;
    end process;

    read_addr_next <= read_addr + to_int(read_ready_ram and read_valid_ram);


    ------------------------------------------------------------------------------
    -- This value is not used in the write clock domain if we are in drop_packet mode
    resync_write_addr : if not enable_drop_packet generate
      resync_counter_inst : entity resync.resync_counter
        generic map (
          width => write_addr'length
        )
        port map (
          clk_in      => clk_write,
          counter_in  => write_addr,
          clk_out     => clk_read,
          counter_out => write_addr_resync
        );
    end generate;


    ------------------------------------------------------------------------------
    -- This value is used in the write clock domain only if we are in packet mode
    resync_num_lasts_written : if enable_packet_mode generate
      resync_counter_inst : entity resync.resync_counter
        generic map (
          width => num_lasts_written'length
        )
        port map (
          clk_in      => clk_write,
          counter_in  => num_lasts_written,
          clk_out     => clk_read,
          counter_out => num_lasts_written_resync
        );
    end generate;
  end block;


  ------------------------------------------------------------------------------
  memory : block
    constant memory_word_width : integer := width + to_int(enable_last);
    subtype word_t is std_logic_vector(memory_word_width - 1 downto 0);
    type mem_t is array (integer range <>) of word_t;

    signal mem : mem_t(0 to memory_depth - 1) := (others => (others => '0'));
    attribute ram_style of mem : signal is to_attribute(ram_type);

    signal memory_read_data, memory_write_data : word_t;
  begin

    read_data_ram <= memory_read_data(read_data_ram'range);
    memory_write_data(write_data'range) <= write_data;

    assign_data : if enable_last generate
      read_last_ram <= memory_read_data(memory_read_data'high);
      memory_write_data(memory_write_data'high) <= write_last;
    end generate;

    write_memory : process
    begin
      wait until rising_edge(clk_write);

      if write_ready and write_valid then
        mem(to_integer(write_addr(bram_addr_range))) <= memory_write_data;
      end if;
    end process;

    read_memory : process
    begin
      wait until rising_edge(clk_read);

      memory_read_data <= mem(to_integer(read_addr_next(bram_addr_range)));
    end process;
  end block;


  ------------------------------------------------------------------------------
  handshake_pipeline : entity common.handshake_pipeline
    generic map (
      data_width => width,
      full_throughput => true,
      pipeline_control_signals => false,
      -- A pipeline stage will only be added if enable_output_register is true
      -- otherwise this will be a simple route-through
      pipeline_data_signals => enable_output_register
    )
    port map (
      clk => clk_read,
      --
      input_ready => read_ready_ram,
      input_valid => read_valid_ram,
      input_last => read_last_ram,
      input_data => read_data_ram,
      --
      output_ready => read_ready,
      output_valid => read_valid,
      output_last => read_last,
      output_data => read_data
    );

end architecture;
