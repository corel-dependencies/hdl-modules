-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the hdl_modules project.
-- https://hdl-modules.com
-- https://gitlab.com/tsfpga/hdl_modules
-- -------------------------------------------------------------------------------------------------
-- AXI-Lite slave BFM that will perform read/write operations on the
-- :ref:`VUnit memory model <vunit:memory_model>`.
--
-- This entity instantiates :ref:`bfm.axi_lite_read_slave` and/or :ref:`bfm.axi_lite_write_slave`
-- based on what generics are provided.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vc_context;

library axi;
use axi.axi_pkg.all;
use axi.axi_lite_pkg.all;

use work.axi_slave_pkg.all;


entity axi_lite_slave is
  generic (
    axi_read_slave : axi_slave_t := axi_slave_init;
    axi_write_slave : axi_slave_t := axi_slave_init;
    data_width : positive
  );
  port (
    clk : in std_logic;
    --# {{}}
    axi_lite_read_m2s : in axi_lite_read_m2s_t := axi_lite_read_m2s_init;
    axi_lite_read_s2m : out axi_lite_read_s2m_t := axi_lite_read_s2m_init;
    --# {{}}
    axi_lite_write_m2s : in axi_lite_write_m2s_t := axi_lite_write_m2s_init;
    axi_lite_write_s2m : out axi_lite_write_s2m_t := axi_lite_write_s2m_init
  );
end entity;

architecture a of axi_lite_slave is

begin

  ------------------------------------------------------------------------------
  axi_read_slave_gen : if axi_read_slave /= axi_slave_init generate

    axi_lite_read_slave_inst : entity work.axi_lite_read_slave
      generic map (
        axi_slave => axi_read_slave,
        data_width => data_width
      )
      port map (
        clk => clk,
        --
        axi_lite_read_m2s => axi_lite_read_m2s,
        axi_lite_read_s2m => axi_lite_read_s2m
      );
  end generate;


  ------------------------------------------------------------------------------
  axi_write_slave_gen : if axi_write_slave /= axi_slave_init generate

    axi_lite_write_slave_inst : entity work.axi_lite_write_slave
      generic map (
        axi_slave => axi_write_slave,
        data_width => data_width
      )
      port map (
        clk => clk,
        --
        axi_lite_write_m2s => axi_lite_write_m2s,
        axi_lite_write_s2m => axi_lite_write_s2m
      );

  end generate;


end architecture;
