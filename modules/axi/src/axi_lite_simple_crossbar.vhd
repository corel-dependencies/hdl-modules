-- -------------------------------------------------------------------------------------------------
-- Simple N-to-1 crossbar for connecting multiple AXI-Lite masters to one port.
-- Wraps axi_lite_simple_write_crossbar and axi_lite_simple_read_crossbar.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library axi;
use axi.axi_lite_pkg.all;

entity axi_lite_simple_crossbar is
  generic(
    num_inputs : integer
    );
  port(
    clk             : in  std_logic;
    rst_n           : in  std_ulogic;
    --
    input_ports_m2s : in  axi_lite_m2s_vec_t(0 to num_inputs - 1) := (others => axi_lite_m2s_init);
    input_ports_s2m : out axi_lite_s2m_vec_t(0 to num_inputs - 1);
    --
    output_m2s      : out axi_lite_m2s_t;
    output_s2m      : in  axi_lite_s2m_t                          := axi_lite_s2m_init
    );
end entity;

architecture a of axi_lite_simple_crossbar is

  signal input_ports_read_m2s : axi_lite_read_m2s_vec_t(0 to num_inputs - 1);
  signal input_ports_read_s2m : axi_lite_read_s2m_vec_t(0 to num_inputs - 1);

  signal output_read_m2s : axi_lite_read_m2s_t := axi_lite_read_m2s_init;
  signal output_read_s2m : axi_lite_read_s2m_t := axi_lite_read_s2m_init;

  signal input_ports_write_m2s : axi_lite_write_m2s_vec_t(0 to num_inputs - 1);
  signal input_ports_write_s2m : axi_lite_write_s2m_vec_t(0 to num_inputs - 1);

  signal output_write_m2s : axi_lite_write_m2s_t;
  signal output_write_s2m : axi_lite_write_s2m_t;

begin

  input_ports_loop : for input_idx in input_ports_m2s'range generate
    input_ports_read_m2s(input_idx) <= input_ports_m2s(input_idx).read;
    input_ports_s2m(input_idx).read <= input_ports_read_s2m(input_idx);
    output_m2s.read                 <= output_read_m2s;
    output_read_s2m                 <= output_s2m.read;

    input_ports_write_m2s(input_idx) <= input_ports_m2s(input_idx).write;
    input_ports_s2m(input_idx).write <= input_ports_write_s2m(input_idx);
    output_m2s.write                 <= output_write_m2s;
    output_write_s2m                 <= output_s2m.write;
  end generate;

  axi_lite_simple_read_crossbar_inst : entity work.axi_lite_simple_read_crossbar
    generic map (
      num_inputs => num_inputs)
    port map (
      clk             => clk,
      rst_n           => rst_n,
      input_ports_m2s => input_ports_read_m2s,
      input_ports_s2m => input_ports_read_s2m,
      output_m2s      => output_read_m2s,
      output_s2m      => output_read_s2m);

  axi_lite_simple_write_crossbar_inst : entity work.axi_lite_simple_write_crossbar
    generic map (
      num_inputs => num_inputs)
    port map (
      clk             => clk,
      rst_n           => rst_n,
      input_ports_m2s => input_ports_write_m2s,
      input_ports_s2m => input_ports_write_s2m,
      output_m2s      => output_write_m2s,
      output_s2m      => output_write_s2m);

end architecture;
