-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the hdl_modules project, a collection of reusable, high-quality,
-- peer-reviewed VHDL building blocks.
-- https://hdl-modules.com
-- https://gitlab.com/hdl_modules/hdl_modules
-- -------------------------------------------------------------------------------------------------
-- Wrapper around VUnit BFM that uses convenient record types for the AXI-Lite signals.
--
-- Instantiates the VUnit ``axi_read_slave`` verification component, which acts as an AXI slave
-- and reads data from the :ref:`VUnit memory model <vunit:memory_model>`.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library axi;
use axi.axi_pkg.all;
use axi.axi_lite_pkg.all;

library vunit_lib;
context vunit_lib.vc_context;


entity axi_lite_read_slave is
  generic (
    axi_slave : axi_slave_t;
    data_width : positive
  );
  port (
    clk : in std_ulogic;
    --# {{}}
    axi_lite_read_m2s : in axi_lite_read_m2s_t := axi_lite_read_m2s_init;
    axi_lite_read_s2m : out axi_lite_read_s2m_t := axi_lite_read_s2m_init
  );
end entity;

architecture a of axi_lite_read_slave is

  constant len : std_ulogic_vector(axi_a_len_sz - 1 downto 0) := std_logic_vector(to_len(1));
  constant size : std_ulogic_vector(axi_a_size_sz - 1 downto 0) :=
    std_logic_vector(to_size(data_width));

  -- Using "open" not ok in GHDL: unconstrained port "rid" must be connected
  signal rid, aid : std_ulogic_vector(8 - 1 downto 0) := (others => '0');

  signal araddr : std_ulogic_vector(axi_lite_read_m2s.ar.addr'range);

begin

  ------------------------------------------------------------------------------
  axi_read_slave_inst : entity vunit_lib.axi_read_slave
    generic map (
      axi_slave => axi_slave
    )
    port map (
      aclk => clk,
      --
      arvalid => axi_lite_read_m2s.ar.valid,
      arready => axi_lite_read_s2m.ar.ready,
      arid => aid,
      araddr => araddr,
      arlen => len,
      arsize => size,
      arburst => axi_a_burst_fixed,
      --
      rvalid => axi_lite_read_s2m.r.valid,
      rready => axi_lite_read_m2s.r.ready,
      rid => rid,
      rdata => axi_lite_read_s2m.r.data(data_width - 1 downto 0),
      rresp => axi_lite_read_s2m.r.resp,
      rlast => open
    );

  araddr <= std_logic_vector(axi_lite_read_m2s.ar.addr);

end architecture;
