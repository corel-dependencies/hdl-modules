-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the tsfpga project.
-- https://tsfpga.com
-- https://gitlab.com/tsfpga/tsfpga
-- -------------------------------------------------------------------------------------------------
-- Wrapper that selects synchronous/asynchronous FIFO or passthrough depending on on generic values.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library common;
use common.attribute_pkg.all;


entity fifo_wrapper is
  generic (
    use_asynchronous_fifo : boolean;
    -- Generics for the FIFOs.
    -- Note that the default values are carefully chosen. Must be exactly the same as in fifo.vhd
    -- and asynchronous_fifo.vhd.
    width : positive;
    depth : natural;
    almost_full_level : integer range 0 to depth := depth;
    almost_empty_level : integer range 0 to depth := 0;
    enable_last : boolean := false;
    enable_packet_mode : boolean := false;
    enable_drop_packet : boolean := false;
    ram_type : ram_style_t := ram_style_auto;
    microsemi_flash_device : boolean := false -- Possible on some Microsemi devices, not on Xilinx.
  );
  port (
    -- This clock is used for a synchronous FIFO
    clk : in std_logic;
    rst_n : in std_ulogic;
    -- These clocks are used for an asynchronous FIFO
    clk_read : in std_logic := '0';
    rst_read_n : in std_ulogic := '1';
    clk_write : in std_logic := '0';
    rst_write_n : in std_ulogic := '1';

    read_ready : in  std_logic;
    read_valid : out std_logic;
    read_data : out std_logic_vector(width - 1 downto 0);
    read_last : out std_logic;

    -- Note that this is the same as write_level for a synchronous FIFO.
    read_level : out integer range 0 to depth;
    -- Note that for an asynchronous FIFO, this signal is in the "read" clock domain.
    almost_empty : out std_logic;

    write_ready : out std_logic;
    write_valid : in  std_logic;
    write_data : in  std_logic_vector(width - 1 downto 0);
    write_last : in std_logic := '0';

    -- Note that this is the same as read_level for a synchronous FIFO.
    write_level : out integer range 0 to depth;
    -- Note that for an asynchronous FIFO, this signal is in the "write" clock domain.
    almost_full : out std_logic;

    -- Note that for an asynchronous FIFO, this signal is in the "write" clock domain
    drop_packet : in std_logic := '0'
  );
end entity;

architecture a of fifo_wrapper is

begin

  choose_fifo : if depth = 0 generate

    assert not enable_packet_mode report "Can not use packet mode without FIFO";
    assert not enable_drop_packet report "Can not use drop packet without FIFO";

    write_ready <= read_ready;
    read_valid <= write_valid;
    read_data <= write_data;
    read_last <= write_last;

  elsif use_asynchronous_fifo generate

    ------------------------------------------------------------------------------
    asynchronous_fifo_inst : entity work.asynchronous_fifo
      generic map (
        width => width,
        depth => depth,
        almost_full_level => almost_full_level,
        almost_empty_level => almost_empty_level,
        enable_last => enable_last,
        enable_packet_mode => enable_packet_mode,
        enable_drop_packet => enable_drop_packet,
        ram_type => ram_type,
        microsemi_flash_device => microsemi_flash_device
      )
      port map (
        clk_read => clk_read,
        rst_read_n => rst_read_n,
        read_ready => read_ready,
        read_valid => read_valid,
        read_data => read_data,
        read_last => read_last,
        --
        read_level => read_level,
        read_almost_empty => almost_empty,
        --
        clk_write => clk_write,
        rst_write_n => rst_write_n,
        write_ready => write_ready,
        write_valid => write_valid,
        write_data => write_data,
        write_last => write_last,
        --
        write_level => write_level,
        write_almost_full => almost_full,
        --
        drop_packet => drop_packet
      );

  else generate

    ------------------------------------------------------------------------------
    fifo_inst : entity work.fifo
      generic map (
        width => width,
        depth => depth,
        almost_full_level => almost_full_level,
        almost_empty_level => almost_empty_level,
        enable_last => enable_last,
        enable_packet_mode => enable_packet_mode,
        enable_drop_packet => enable_drop_packet,
        ram_type => ram_type,
        microsemi_flash_device => microsemi_flash_device
      )
      port map (
        clk => clk,
        rst_n => rst_n,
        level => read_level,
        --
        read_ready => read_ready,
        read_valid => read_valid,
        read_data => read_data,
        read_last => read_last,
        almost_empty => almost_empty,
        --
        write_ready => write_ready,
        write_valid => write_valid,
        write_data => write_data,
        write_last => write_last,
        almost_full => almost_full,
        --
        drop_packet => drop_packet
      );

    write_level <= read_level;

  end generate;


end architecture;
