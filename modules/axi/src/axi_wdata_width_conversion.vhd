-------------------------------------------------------------------------------
-- axi lite write data width conversion.
--
-- If word_endianness is "big" then the write data word 0xAAAABBBB will be
-- output as 0XAAAA first, otherwise 0xBBBB first (16 o_output_data in this case.)
--
-- Note: write response slverr will be sent if input is not read when
-- bus writes.  o_overflow will be asseretd as well.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library common;
use common.types_pkg.all;

library axi;
use axi.axi_lite_pkg.all;
use axi.axi_pkg.all;

entity axi_wdata_width_conversion is
  generic (
    output_width   : positive;
    word_endianness : string := "big";
    big_endian      : boolean := true    -- strobe endianness
    );
  port (
    clk             : in  std_ulogic;
    rst_n           : in  std_ulogic;
    --
    i_axi_lite_m2s  : in  axi_lite_m2s_t;
    o_axi_lite_s2m  : out axi_lite_s2m_t;
    --
    i_output_ready  : in  std_ulogic;
    o_output_valid  : out std_ulogic;
    o_output_data   : out std_ulogic_vector(output_width - 1 downto 0);
    o_output_strobe : out std_ulogic;
    o_overflow      : out std_ulogic
    );
end entity;

architecture a of axi_wdata_width_conversion is

  -- wc conversion atom is the chunk of input data validated by one wc input
  -- strobe bit.
  constant c_wc_number_of_atoms_per_input : integer := axi_lite_data_sz / o_output_data'length;

  signal s_input_data   : std_ulogic_vector(axi_lite_data_sz - 1 downto 0);
  signal s_input_strobe : std_ulogic_vector(c_wc_number_of_atoms_per_input - 1 downto 0);
  signal s_input_valid  : std_ulogic;
  signal s_input_ready  : std_ulogic;

  signal s_dump : std_ulogic;

  type t_atom_rec is record
    atom   : std_ulogic_vector(o_output_data'range);
    strobe : std_ulogic;
  end record t_atom_rec;
  type t_atom_ar is array (0 to c_wc_number_of_atoms_per_input-1) of t_atom_rec;

  impure function to_atom_ar return t_atom_ar is

    -- If output width < 8:
    -- how many bits of axi write strobe (to be ORed) correspond to one bit of
    -- wc input strobe.
    constant c_strobe_atom_width_lt8 : integer := maximum(1, (axi_lite_data_sz / axi_lite_w_strb_sz) / o_output_data'length);

    -- If output width >= 8:
    -- how many bits of wc input_strobe correspond to one bit of axi write strobe.
    constant c_strobe_atom_width_me8 : integer := o_output_data'length / (axi_lite_data_sz / axi_lite_w_strb_sz);  --

    variable y              : t_atom_ar;
    variable v_input_strobe : std_ulogic_vector(axi_lite_w_strb_sz - 1 downto 0);
  begin
    if big_endian then
      v_input_strobe := swap_bit_order(i_axi_lite_m2s.write.w.strb);
    else
      v_input_strobe := i_axi_lite_m2s.write.w.strb;
    end if;

    for i in y'range loop
      y(i).atom := i_axi_lite_m2s.write.w.data((i+1)*o_output_data'length - 1 downto i*o_output_data'length);
    end loop;

    if o_output_data'length < 8 then

      for i in 0 to axi_lite_w_strb_sz-1 loop
        for j in 0 to c_strobe_atom_width_lt8 - 1 loop
          y(i*c_strobe_atom_width_lt8 + j).strobe := v_input_strobe(i);
        end loop;
      end loop;

    else

      for i in y'range loop
        y(i).strobe := or v_input_strobe((i+1) * c_strobe_atom_width_me8 - 1
                                         downto i * c_strobe_atom_width_me8);
      end loop;
    end if;

    return y;
  end function to_atom_ar;

  function get_wstrobe(
    x : t_atom_ar
    ) return std_ulogic_vector is
    variable y : std_ulogic_vector(s_input_strobe'range);
  begin
    for i in y'range loop
      y(i) := x(i).strobe;
    end loop;

    return y;
  end function get_wstrobe;

  function get_wdata(
    x : t_atom_ar
    ) return std_ulogic_vector is
    variable y : std_ulogic_vector(s_input_data'range);
  begin
    for i in x'range loop
      y((i+1)*o_output_data'length - 1 downto i*o_output_data'length) := x(i).atom;
    end loop;

    return y;
  end function get_wdata;

  function swap_wc_input (
    x : t_atom_ar)
    return t_atom_ar is
    variable y : t_atom_ar;
  begin
    for i in y'range loop
      y(y'high - i) := x(i);
    end loop;

    return y;
  end function swap_wc_input;

  signal s_pipeline_slave_m2s : axi_lite_m2s_t;
  signal s_pipeline_slave_s2m : axi_lite_s2m_t;

begin


  -- At overflow, assert o_overflow and dump width conversion instance at
  -- overflow, driving s_dump for a few clock cycles when o_overflow is
  -- asserted.
  overflow_proc : process (clk, rst_n) is
    constant c_dump_length : natural    := 4;
    variable v_cnt         : natural;
    variable v_overflow    : std_ulogic;
  begin
    if not rst_n then
      o_overflow <= '0';
      s_dump <= '0';
      v_overflow := '0';
      v_cnt := 0;
    elsif rising_edge(clk) then
      o_overflow <= '0';
      s_dump     <= '0';

      v_overflow := s_input_valid and not i_output_ready;

      if v_overflow then
        o_overflow <= '1';
        v_cnt      := c_dump_length-1;
      elsif v_cnt /= 0 then
        v_cnt  := v_cnt-1;
        s_dump <= '1';
      end if;
    end if;
  end process overflow_proc;

  axi_lite_pipeline_inst : entity axi.axi_lite_pipeline
    generic map (
      data_width => axi_lite_data_sz,
      addr_width => axi_a_addr_sz)
    port map (
      clk        => clk,
      rst_n => rst_n,
      master_m2s => i_axi_lite_m2s,
      master_s2m => o_axi_lite_s2m,
      slave_m2s  => s_pipeline_slave_m2s,
      slave_s2m  => s_pipeline_slave_s2m);

  axi_pipeline_proc : process (all) is
  begin
    s_pipeline_slave_s2m.write.w.ready  <= s_input_ready;
    s_input_valid                       <= s_pipeline_slave_m2s.write.w.valid;
    s_pipeline_slave_s2m.write.aw.ready <= '1';
    s_pipeline_slave_s2m.write.b.valid  <= s_pipeline_slave_m2s.write.w.valid and
                                          s_pipeline_slave_s2m.write.w.ready;

    if i_output_ready then
      s_pipeline_slave_s2m.write.b.resp <= axi_resp_okay;
    else
      s_pipeline_slave_s2m.write.w.ready <= '1';
      s_pipeline_slave_s2m.write.b.resp  <= axi_resp_slverr;
    end if;
  end process axi_pipeline_proc;

  gen_width_conversion : if axi_lite_data_sz /= o_output_data'length generate

    width_conversion_inst : entity common.width_conversion
      generic map (
        input_width       => axi_lite_data_sz,
        output_width      => output_width,
        enable_strobe     => true,
        strobe_unit_width => output_width)
      port map (
        clk              => clk,
        rst_n            => rst_n,
        input_ready      => s_input_ready,
        input_valid      => s_input_valid,
        input_last       => '0',
        input_data       => s_input_data,
        input_strobe     => s_input_strobe,
        output_ready     => i_output_ready or s_dump,
        output_valid     => o_output_valid,
        output_last      => open,
        output_data      => o_output_data,
        output_strobe(0) => o_output_strobe);

  else generate

    s_input_ready   <= '1';
    o_output_valid  <= s_input_valid;
    o_output_data   <= s_pipeline_slave_m2s.write.w.data;
    o_output_strobe <= s_input_strobe(0);

  end generate;

  wc_input_proc : process (all) is
    variable v_atom_ar         : t_atom_ar;
    variable v_atom_ar_swapped : t_atom_ar;
  begin
    v_atom_ar         := to_atom_ar;
    v_atom_ar_swapped := swap_wc_input(v_atom_ar);

    s_input_strobe <= get_wstrobe(v_atom_ar_swapped);

    if word_endianness = "little" then
      s_input_data <= get_wdata(v_atom_ar);
    elsif word_endianness = "big" then
      s_input_data <= get_wdata(v_atom_ar_swapped);
    end if;
  end process wc_input_proc;

end architecture;
