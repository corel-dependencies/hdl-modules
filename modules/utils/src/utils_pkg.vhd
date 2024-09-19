library ieee;
context ieee.ieee_std_context;

library extras_2008;
use extras_2008.common.all;

library common;
use common.types_pkg.all;

library axi;
use axi.axi_pkg.all;
use axi.axi_lite_pkg.all;
use axi.axi_stream_pkg.all;

package utils_pkg is

  type t_bit_order is (little_endian, big_endian);

  function to_sulv_big (
    x : sulv_array)
    return std_ulogic_vector;

  function to_sulv_big (
    x : unsigned_array)
    return std_ulogic_vector;

  function to_sulv_little (
    x : sulv_array)
    return std_ulogic_vector;

  function to_sulv_little (
    x : unsigned_array)
    return std_ulogic_vector;

  function to_unsigned (
    x : unsigned_array)
    return unsigned;

  function to_unsigned (
    x : sulv_array)
    return unsigned;

  -- N-size std_ulogic_vector to CHUNK_SIZE x (N/CHUNK_SIZE) sulv_array.
  function to_sulv_array (
    constant CHUNK_SIZE : in positive;
    x                   :    std_ulogic_vector)
    return sulv_array;

  -- N-size unsigned to CHUNK_SIZE x (N/CHUNK_SIZE) sulv_array.
  function to_sulv_array (
    constant CHUNK_SIZE : in positive;
    x                   :    unsigned)
    return sulv_array;

  -- M x N sulv_array to CHUNK_SIZE x (MxN/CHUNK_SIZE) sulv_array.
  function to_sulv_array (
    constant CHUNK_SIZE : in positive;
    x                   :    sulv_array)
    return sulv_array;

  -- N-size std_ulogic_vector to CHUNK_SIZE x (N/CHUNK_SIZE) unsigned_array.
  function to_unsigned_array (
    constant CHUNK_SIZE : in positive;
    x                   :    std_ulogic_vector)
    return unsigned_array;

  function to_unsigned_array (
    constant CHUNK_SIZE : in positive;
    x                   :    unsigned)
    return unsigned_array;

  function shift_right (
    x     : sulv_array;
    count : natural
    )
    return sulv_array;

  function shift_right (
    x     : unsigned_array;
    count : natural
    )
    return unsigned_array;

  function shift_left (
    x     : sulv_array;
    count : natural
    )
    return sulv_array;

  function shift_left (
    x     : unsigned_array;
    count : natural
    )
    return unsigned_array;

  function "+" (L : unsigned_array; R : integer)
    return unsigned_array;

  function "-" (L : unsigned_array; R : integer)
    return unsigned_array;

end package utils_pkg;

package body utils_pkg is

  -- sulv_array to std_ulogic_vector.  Little endian.
  function to_sulv_little (
    x : sulv_array)
    return std_ulogic_vector is
    variable y : std_ulogic_vector(x'length*x'element'length-1 downto 0);
  begin
    for i in 0 to x'high loop
      y((i+1)*x'element'length - 1 downto i*x'element'length) := x(i);
    end loop;

    return y;
  end function;

  function to_sulv_little (
    x : unsigned_array)
    return std_ulogic_vector is
  begin
    return to_sulv_little(to_sulv_array(x));
  end function;

  -- sulv_array to std_ulogic_vector.  Big endian.
  function to_sulv_big (
    x : sulv_array)
    return std_ulogic_vector is
    variable y : std_ulogic_vector(x'length*x'element'length-1 downto 0);
  begin
    for i in 0 to x'high loop
      y(y'high - i*x'element'length downto y'high+1 - (i+1)*x'element'length) := x(i);
    end loop;

    return y;
  end function;

  function to_sulv_big (
    x : unsigned_array)
    return std_ulogic_vector is
  begin
    return to_sulv_big(to_sulv_array(x));
  end function;

  function to_unsigned (
    x : unsigned_array)
    return unsigned is
  begin
    return unsigned(to_sulv_big(x));
  end function;

  function to_unsigned (
    x : sulv_array)
    return unsigned is
  begin
    return unsigned(to_sulv_big(x));
  end function;

  function to_sulv_array (
    constant CHUNK_SIZE : in positive;  -- inner dimension of the output sulv_array
    x                   :    std_ulogic_vector)
    return sulv_array is
    constant C_SULV_ARRAY_LENGTH : natural := x'length / CHUNK_SIZE;
    variable y                   : sulv_array(C_SULV_ARRAY_LENGTH-1 downto 0)(CHUNK_SIZE-1 downto 0);
  begin
    for i in 0 to C_SULV_ARRAY_LENGTH-1 loop
      y(y'high-i) := x(x'low + (i+1)*CHUNK_SIZE-1 downto x'low + i*CHUNK_SIZE);
    end loop;
    return y;
  end function;

  function to_sulv_array (
    constant CHUNK_SIZE : in positive;
    x                   :    unsigned)
    return sulv_array is
  begin
    return to_sulv_array(CHUNK_SIZE => CHUNK_SIZE, x => std_ulogic_vector(x));
  end function;

  function to_sulv_array (
    constant CHUNK_SIZE : in positive;  -- inner dimension of the output sulv_array
    x                   :    sulv_array)
    return sulv_array is
    constant C_SULV_ARRAY_LENGTH : natural := x'length * x'element'length / CHUNK_SIZE;
    variable y                   : sulv_array(0 to C_SULV_ARRAY_LENGTH-1)(CHUNK_SIZE-1 downto 0);
  begin
    y := to_sulv_array(y'element'length, to_sulv_big(x));

    return y;
  end function;

  function to_unsigned_array (
    constant CHUNK_SIZE : in positive;
    x                   :    std_ulogic_vector)
    return unsigned_array is
  begin
    return to_unsigned_array(to_sulv_array(CHUNK_SIZE => CHUNK_SIZE, x => x));
  end function;

  function to_unsigned_array (
    constant CHUNK_SIZE : in positive;
    x                   :    unsigned)
    return unsigned_array is
  begin
    return to_unsigned_array(CHUNK_SIZE, std_ulogic_vector(x));
  end function;

  function shift_right (
    x     : sulv_array;
    count : natural
    )
    return sulv_array is
    variable y : sulv_array(x'range)(x'element'range) := (others => (others => '-'));
  begin
    if x'ascending then
      for i in count to x'high loop
        y(i) := x(i-count);
      end loop;
    else
      for i in x'high-count downto 0 loop
        y(i) := x(i+count);
      end loop;
    end if;

    return y;
  end function;

  function shift_right (
    x     : unsigned_array;
    count : natural
    )
    return unsigned_array is
  begin
    return to_unsigned_array(shift_right(to_sulv_array(x), count));
  end function;

  function shift_left (
    x     : sulv_array;
    count : natural
    )
    return sulv_array is
    variable y : sulv_array(x'range)(x'element'range) := (others => (others => '-'));
  begin
    if x'ascending then
      for i in x'high-count downto 0 loop
        y(i) := x(i+count);
      end loop;
    else
      for i in count to x'high loop
        y(i) := x(i-count);
      end loop;
    end if;

    return y;
  end function;

  function shift_left (
    x     : unsigned_array;
    count : natural
    )
    return unsigned_array is
  begin
    return to_unsigned_array(shift_left(to_sulv_array(x), count));
  end function;

  -- Convert to unsigned, increase, convert back into unsigned_array.
  function "+" (L : unsigned_array; R : integer)
    return unsigned_array is
    variable v_uns : unsigned(L'length*L'element'length - 1 downto 0);
  begin
    v_uns := to_unsigned(L);
    v_uns := v_uns + R;

    return to_unsigned_array(L'element'length, v_uns);
  end function;

  -- Convert to unsigned, decrease, convert back into unsigned_array.
  function "-" (L : unsigned_array; R : integer)
    return unsigned_array is
    variable v_uns : unsigned(L'length*L'element'length - 1 downto 0);
  begin
    v_uns := to_unsigned(L);
    v_uns := v_uns - R;

    return to_unsigned_array(L'element'length, v_uns);
  end function;

end package body utils_pkg;
