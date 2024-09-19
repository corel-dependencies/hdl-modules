-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the tsfpga project.
-- https://tsfpga.com
-- https://gitlab.com/tsfpga/tsfpga
-- -------------------------------------------------------------------------------------------------
-- Simple debounce mechanism to be used with e.g. the signal from a button or
-- dip switch. It eliminates noise by requiring the input to have a stable
-- value for a specified number of clock cycles before propagating the value.
--
-- Uses a resync_level block (async_reg chain) to make sure the input is not
-- metastable.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library resync;


entity debounce is
  generic (
    -- Number of cycles the input must be stable for the value to propagate to the result side.
    stable_count : positive
    );
  port (
    -- Input value that may be metastable and noisy
    noisy_input   : in  std_logic := '0';
    --
    clk           : in  std_logic;
    rst_n         : in  std_ulogic;
    stable_result : out std_logic
    );
end entity;

architecture a of debounce is

  signal noisy_input_resync        : std_logic;
  signal num_cycles_with_new_value : integer range 0 to stable_count - 1;

begin

  ------------------------------------------------------------------------------
  resync_level_inst : entity resync.resync_level
    generic map (
      -- We do not know the input clock, so set this to false
      enable_input_register => false
      )
    port map (
      data_in   => noisy_input,
      --
      clk_out   => clk,
      rst_out_n => rst_n,
      data_out  => noisy_input_resync
      );


  ------------------------------------------------------------------------------
  main : process (clk, rst_n) is
  begin
    if not rst_n then
      stable_result             <= '0';
      num_cycles_with_new_value <= 0;
    elsif rising_edge(clk) then

      if noisy_input_resync = stable_result then
        num_cycles_with_new_value <= 0;

      else
        if num_cycles_with_new_value = stable_count - 1 then
          stable_result             <= noisy_input_resync;
          num_cycles_with_new_value <= 0;
        else
          num_cycles_with_new_value <= num_cycles_with_new_value + 1;
        end if;
      end if;

    end if;
  end process;

end architecture;
