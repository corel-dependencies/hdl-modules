-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the tsfpga project.
-- https://tsfpga.com
-- https://gitlab.com/tsfpga/tsfpga
-- -------------------------------------------------------------------------------------------------
-- Synchronize a counter value between two domains
--
-- This module assumes that the input counter value only increments
-- and decrements in steps of one.
--
-- Note that unlike e.g. resync_level, it is safe to drive the input of this entity with LUTs
-- as well as FFs.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library common;
use common.attribute_pkg.all;

library math;
use math.math_pkg.all;


entity resync_counter is
  generic (
    width           : positive;
    -- Initial value for the ouput that will be set for a few cycles before the first input
    -- value has propagated.
    default_value   : unsigned(width - 1 downto 0) := (others => '0');
    -- Optional pipeline step on the output after Gray conversion
    pipeline_output : boolean                      := false
    );
  port (
    clk_in     : in std_logic;
    rst_in_n   : in std_ulogic;
    counter_in : in unsigned(default_value'range);

    clk_out     : in  std_logic;
    rst_out_n   : in  std_ulogic;
    counter_out : out unsigned(default_value'range)
    );
end entity;

architecture a of resync_counter is
  signal counter_in_gray, counter_in_gray_p1, counter_out_gray : std_logic_vector(counter_in'range);

  attribute dont_touch of counter_in_gray   : signal is "true";
  attribute async_reg of counter_in_gray_p1 : signal is "true";
  attribute async_reg of counter_out_gray   : signal is "true";
begin

  ------------------------------------------------------------------------------
  clk_in_process : process (clk_in, rst_in_n) is
  begin
    if not rst_in_n then
      counter_in_gray <= to_gray(default_value);
    elsif rising_edge(clk_in) then

      counter_in_gray <= to_gray(counter_in);

    end if;
  end process;


  ------------------------------------------------------------------------------
  clk_out_process : process (clk_out, rst_out_n) is
  begin
    if not rst_out_n then
      counter_out_gray   <= to_gray(default_value);
      counter_in_gray_p1 <= to_gray(default_value);
    elsif rising_edge(clk_out) then

      counter_out_gray   <= counter_in_gray_p1;
      counter_in_gray_p1 <= counter_in_gray;

    end if;
  end process;


  ------------------------------------------------------------------------------
  optional_output_pipe : if pipeline_output generate

    pipe : process (clk_out, rst_out_n) is
    begin
      if not rst_out_n then
        counter_out <= default_value;
      elsif rising_edge(clk_out) then

        counter_out <= from_gray(counter_out_gray);

      end if;
    end process;

  else generate

    counter_out <= from_gray(counter_out_gray);

  end generate;

end architecture;
