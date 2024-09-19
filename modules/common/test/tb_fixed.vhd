library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.fixed_pkg.all;

library vunit_lib;
context vunit_lib.vunit_context;

use work.types_pkg.all;


entity tb_fixed is
  generic (
    runner_cfg : string
  );
end entity;

architecture tb of tb_fixed is

begin

  main : process

    variable udata0 : ufixed(-1 downto -2) := "11";

    variable sdata0 : sfixed(-1 downto -2) := "11";
    variable sdata1 : sfixed(-1 downto -2) := "01";

  begin
    test_runner_setup(runner, runner_cfg);

    if run("ufixed") then
      check_equal(to_real(udata0), 0.75);

    elsif run("sfixed") then
      check_equal(to_real(sdata0), -0.25);
      check_equal(to_real(sdata1), 0.25);

    end if;

    test_runner_cleanup(runner);
    wait;
  end process;

end architecture;
