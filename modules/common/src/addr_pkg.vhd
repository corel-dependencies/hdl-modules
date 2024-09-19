-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the tsfpga project.
-- https://tsfpga.com
-- https://gitlab.com/tsfpga/tsfpga
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library math;
use math.math_pkg.all;


package addr_pkg is

  constant addr_width : integer := 32;
  subtype addr_t is unsigned(addr_width - 1 downto 0);
  type addr_vec_t is array (integer range <>) of addr_t;

  type addr_and_mask_t is record
    addr : addr_t;
    mask : addr_t;
  end record;
  type addr_and_mask_vec_t is array (integer range <>) of addr_and_mask_t;

  function addr_bits_needed(addrs : addr_and_mask_vec_t) return positive;

  function match(addr : unsigned; addr_and_mask : addr_and_mask_t) return boolean;

  function decode(addr : unsigned; addrs : addr_and_mask_vec_t) return integer;

  function calc_addr_and_mask_mux(nbits   : positive;
                                  nslaves : positive
                                  ) return addr_and_mask_vec_t;
  procedure pretty_print (
    addr_and_mask : addr_and_mask_vec_t);

end package;

package body addr_pkg is

  function addr_bits_needed(addrs : addr_and_mask_vec_t) return positive is
    variable result : positive := 1;
  begin
    -- Return the number of bits that are needed to decode and handle the addresses.
    for addr_idx in addrs'range loop
      result := maximum(result, num_bits_needed(addrs(addr_idx).mask));
    end loop;
    return result;
  end function;

  function match(addr : unsigned; addr_and_mask : addr_and_mask_t) return boolean is
    variable test_ok : boolean := true;
  begin
    for bit_idx in addr_and_mask.addr'range loop
      if addr_and_mask.mask(bit_idx) then
        test_ok := test_ok and (addr(bit_idx) = addr_and_mask.addr(bit_idx));
      end if;
    end loop;

    return test_ok;
  end function;

  function decode(addr : unsigned; addrs : addr_and_mask_vec_t) return integer is
    constant decode_fail : integer := addrs'length;
  begin
    for addr_idx in addrs'range loop
      if match(addr, addrs(addr_idx)) then
        return addr_idx;
      end if;
    end loop;

    return decode_fail;
  end function;

  -- Return the address mask to address nslaves slaves.
  -- nbits: number of addr bits needed by the slave.
  function calc_mask(nbits   : positive;
                     nslaves : positive)
    return addr_t is
    variable v_result : addr_t := (others => '0');
  begin
    v_result(nbits + num_bits_needed(nslaves-1) - 1 downto nbits) := (others => '1');
    return v_result;
  end function;

  -- Return the address_and_mask_vec_t (base address and mask) to address
  -- nslaves slaves.
  -- nbits: number of addr bits needed by the slave.
  function calc_addr_and_mask_mux(nbits   : positive;
                                  nslaves : positive)
    return addr_and_mask_vec_t is
    constant C_MASK   : addr_t := calc_mask(nbits, nslaves);
    variable v_result : addr_and_mask_vec_t(0 to nslaves-1);
  begin
    for idx in 0 to nslaves-1 loop
      v_result(idx).mask := C_MASK;
      v_result(idx).addr := shift_left(to_unsigned(idx, v_result(idx).addr'length), nbits);
    end loop;
    return v_result;
  end function;

  procedure pretty_print (
    addr_and_mask : addr_and_mask_vec_t) is
  begin
    for i in addr_and_mask'range loop
      report integer'image(i) & " => (" &
        to_hstring(addr_and_mask(i).addr) & ", " &
        to_hstring(addr_and_mask(i).mask) & ")" & lf;
    end loop;
  end procedure;

end package body;
