library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;
context vunit_lib.com_context;
context vunit_lib.vc_context;

library extras_2008;
use extras_2008.common.all;

library common;
use common.types_pkg.all;

library axi;
use axi.axi_pkg.all;
use axi.axi_lite_pkg.all;
use axi.axi_stream_pkg.all;

package sim_utils_pkg is

  -- pragma translate_off
  procedure push_stream_by_byte_big (
    signal net        : inout std_ulogic;
    master_stream     :       stream_master_t;
    constant i_wdata : in    std_logic_vector  -- length multiple of 8
    );

  procedure push_stream_by_byte_little (
    signal net        : inout std_ulogic;
    master_stream     :       stream_master_t;
    constant i_wdata : in    std_logic_vector  -- length multiple of 8
    );

  procedure pop_stream_by_byte_big (
    signal net        : inout std_ulogic;
    slave_stream     :       stream_slave_t;
    o_data : out std_ulogic_vector
    );

  procedure check_stream_by_byte (
    signal net        : inout std_ulogic;
    slave_stream      :       stream_slave_t;
    constant expected : in    std_logic_vector;
    constant msg      : in    string := check_result_tag);

  procedure push_ascii (
    signal net    : inout std_ulogic;
    master_stream :       stream_master_t;
    constant str  : in    string);

  procedure check_stream_ascii (
    signal net        : inout std_ulogic;
    slave_stream      :       stream_slave_t;
    constant expected : in    string;
    constant msg      : in    string := check_result_tag);

  procedure connect_cocotbext_axilmaster (
    signal o_axi_lite_m2s : out axi_lite_m2s_t;
    signal i_axi_lite_s2m : in  axi_lite_s2m_t;

    signal awaddr  : in  std_ulogic_vector(axi_a_addr_sz-1 downto 0);
    signal awprot  : in  std_ulogic_vector(2 downto 0);
    signal awvalid : in  std_ulogic;
    signal awready : out std_ulogic;

    signal wdata  : in  std_ulogic_vector(axi_lite_data_sz-1 downto 0);
    signal wstrb  : in  std_ulogic_vector(axi_lite_w_strb_sz-1 downto 0);
    signal wvalid : in  std_ulogic;
    signal wready : out std_ulogic;

    signal bresp  : out std_ulogic_vector(1 downto 0);
    signal bvalid : out std_ulogic;
    signal bready : in  std_ulogic;

    signal araddr  : in  std_ulogic_vector(axi_a_addr_sz-1 downto 0);
    signal arprot  : in  std_ulogic_vector(2 downto 0);
    signal arvalid : in  std_ulogic;
    signal arready : out std_ulogic;

    signal rdata  : out std_ulogic_vector(axi_lite_data_sz-1 downto 0);
    signal rresp  : out std_ulogic_vector(1 downto 0);
    signal rvalid : out std_ulogic;
    signal rready : in  std_ulogic);

  procedure connect_cocotbext_axismon (
    signal i_axi_stream_m2s : in axi_stream_m2s_t;
    signal i_axi_stream_s2m : in axi_stream_s2m_t;

    signal tdata  : out std_ulogic_vector(axi_stream_data_sz-1 downto 0);
    signal tvalid : out std_ulogic;
    signal tready : out std_ulogic;
    signal tlast  : out std_ulogic;
    signal tuser  : out std_ulogic_vector(axi_stream_user_sz-1 downto 0)
   -- signal tid : out std_ulogic_vector(axi_stream_id_sz-1 downto 0);
   -- signal tdest : out std_ulogic_vector(axi_stream_dest_sz-1 downto 0);
   -- signal tkeep : out std_ulogic_vector(axi_stream_keep_sz-1 downto 0);
   -- signal tstrb : out std_ulogic_vector(axi_stream_strb_sz-1 downto 0)
    );
  -- pragma translate_on

end package sim_utils_pkg;

package body sim_utils_pkg is

  -- pragma translate_off

  -- Push stream each byte in i_wdata.  Big endian first.
  procedure push_stream_by_byte_big (
    signal net        : inout std_ulogic;
    master_stream     :       stream_master_t;
    constant i_wdata : in    std_logic_vector
    ) is  -- length multiple of 8
    variable v_data_asc  : std_ulogic_vector(0 to 7);
    variable v_data_desc : std_ulogic_vector(7 downto 0);
  begin
    assert i_wdata'length mod 8 = 0
      report "i_wdata'length must be a multiple of 8"
      severity error;

    for i in i_wdata'length / 8 - 1 downto 0 loop
      if i_wdata'ascending then
        v_data_asc := i_wdata(i*8 to (i+1)*8-1);
        push_stream(net, master_stream, v_data_asc);
      else
        v_data_desc := i_wdata((i+1)*8-1 downto i*8);
        push_stream(net, master_stream, v_data_desc);
      end if;
    end loop;

  end procedure;

  -- Push stream each byte in i_wdata.  Little endian first.
  procedure push_stream_by_byte_little (
    signal net        : inout std_ulogic;
    master_stream     :       stream_master_t;
    constant i_wdata : in    std_logic_vector  -- length multiple of 8
    ) is
    variable v_data_asc  : std_ulogic_vector(0 to 7);
    variable v_data_desc : std_ulogic_vector(7 downto 0);
  begin
    assert i_wdata'length mod 8 = 0
      report "i_wdata'length must be a multiple of 8"
      severity error;

    for i in 0 to i_wdata'length / 8 - 1 loop
      if i_wdata'ascending then
        v_data_asc := i_wdata(i*8 to (i+1)*8-1);
        push_stream(net, master_stream, v_data_asc);
      else
        v_data_desc := i_wdata((i+1)*8-1 downto i*8);
        push_stream(net, master_stream, v_data_desc);
      end if;
    end loop;

  end procedure;

  -- Pop each byte and compose a multi-byte word.  Assuming big endian.
  procedure pop_stream_by_byte_big (
    signal net        : inout std_ulogic;
    slave_stream     :       stream_slave_t;
    o_data  : out std_ulogic_vector
    ) is
    constant c_nbytes : integer := o_data'length / 8;
    variable v_data : std_ulogic_vector(7 downto 0);
  begin
    assert o_data'length mod 8 = 0
      report "o_data'length (" & integer'image(o_data'length) & ") must be a multiple of 8"
      severity error;

    for i in 0 to c_nbytes-1 loop
      pop_stream(net, slave_stream, v_data);
      o_data(o_data'high - 8*i downto
             o_data'high - 8*(i+1) + 1) := v_data;
    end loop;

  end procedure;

  procedure check_stream_by_byte (
    signal net        : inout std_ulogic;
    slave_stream      :       stream_slave_t;
    constant expected : in    std_logic_vector;
    constant msg      : in    string := check_result_tag) is
    variable v_data_asc  : std_ulogic_vector(0 to 7);
    variable v_data_desc : std_ulogic_vector(7 downto 0);
    variable v_expected, v_got  : std_ulogic_vector(expected'length-1 downto 0) := (others => '0');
  begin
    assert expected'length mod 8 = 0
      report "expected'length (" & integer'image(expected'length) & ") must be a multiple of 8"
      severity error;

    if expected'ascending then
      for i in v_expected'range loop
        v_expected(i) := expected(expected'high-i);
      end loop;
    else
      v_expected := expected;
    end if;

    for i in 0 to expected'length / 8 - 1 loop
      pop_stream(net, slave_stream, v_data_desc);
      v_got(
          v_expected'length-i*8-1 downto
          v_expected'length-(i+1)*8) := v_data_desc;
    end loop;

    check_relation(
      v_got ?= v_expected,
      msg => msg);

  end procedure;

  procedure push_ascii (
    signal net    : inout std_ulogic;
    master_stream :       stream_master_t;
    constant str  : in    string) is
  begin
    for i in str'range loop
      push_stream(net, master_stream, std_ulogic_vector(to_unsigned(character'pos(str(i)), 8)));
    end loop;
  end procedure push_ascii;

  procedure check_stream_ascii (
    signal net        : inout std_ulogic;
    slave_stream      :       stream_slave_t;
    constant expected : in    string;
    constant msg      : in    string := check_result_tag) is
    variable v_data : std_ulogic_vector(0 to 7);
  begin
    for i in expected'range loop
      pop_stream(net, slave_stream, v_data);
      check_equal(character'val(to_integer(unsigned(v_data))),
                  expected(i),
                  msg & " (word " & integer'image(i) & "-th)"
                  );
    end loop;
  end procedure check_stream_ascii;

  -- Connect records axi_lite_s2m_t and axi_lite_m2s_t to equivalent signals
  -- as expected by cocotbext-axi axilmaster cocotb component.  It does not
  -- handle records.
  procedure connect_cocotbext_axilmaster (
    signal o_axi_lite_m2s : out axi_lite_m2s_t;
    signal i_axi_lite_s2m : in  axi_lite_s2m_t;

    signal awaddr  : in  std_ulogic_vector(axi_a_addr_sz-1 downto 0);
    signal awprot  : in  std_ulogic_vector(2 downto 0);
    signal awvalid : in  std_ulogic;
    signal awready : out std_ulogic;

    signal wdata  : in  std_ulogic_vector(axi_lite_data_sz-1 downto 0);
    signal wstrb  : in  std_ulogic_vector(axi_lite_w_strb_sz-1 downto 0);
    signal wvalid : in  std_ulogic;
    signal wready : out std_ulogic;

    signal bresp  : out std_ulogic_vector(1 downto 0);
    signal bvalid : out std_ulogic;
    signal bready : in  std_ulogic;

    signal araddr  : in  std_ulogic_vector(axi_a_addr_sz-1 downto 0);
    signal arprot  : in  std_ulogic_vector(2 downto 0);
    signal arvalid : in  std_ulogic;
    signal arready : out std_ulogic;

    signal rdata  : out std_ulogic_vector(axi_lite_data_sz-1 downto 0);
    signal rresp  : out std_ulogic_vector(1 downto 0);
    signal rvalid : out std_ulogic;
    signal rready : in  std_ulogic) is

  begin

    o_axi_lite_m2s.read.ar.valid <= arvalid;
    o_axi_lite_m2s.read.ar.addr  <= unsigned(araddr);
    arready                      <= i_axi_lite_s2m.read.ar.ready;

    rvalid                      <= i_axi_lite_s2m.read.r.valid;
    rdata                       <= swap_byte_order(i_axi_lite_s2m.read.r.data);
    rresp                       <= i_axi_lite_s2m.read.r.resp;
    o_axi_lite_m2s.read.r.ready <= rready;

    o_axi_lite_m2s.write.aw.valid <= awvalid;
    o_axi_lite_m2s.write.aw.addr  <= unsigned(awaddr);
    awready                       <= i_axi_lite_s2m.write.aw.ready;

    o_axi_lite_m2s.write.w.valid <= wvalid;
    o_axi_lite_m2s.write.w.data  <= swap_byte_order(wdata);
    o_axi_lite_m2s.write.w.strb  <= wstrb;
    wready                       <= i_axi_lite_s2m.write.w.ready;

    bvalid                       <= i_axi_lite_s2m.write.b.valid;
    bresp                        <= i_axi_lite_s2m.write.b.resp;
    o_axi_lite_m2s.write.b.ready <= bready;
  end procedure connect_cocotbext_axilmaster;

  -- Connect records axi_stream_s2m_t and axi_stream_m2s_t to equivalent signals
  -- as expected by cocotbext-axi axis cocotb component.  It does not
  -- handle records.
  procedure connect_cocotbext_axismon (
    signal i_axi_stream_m2s : in axi_stream_m2s_t;
    signal i_axi_stream_s2m : in axi_stream_s2m_t;

    signal tdata  : out std_ulogic_vector(axi_stream_data_sz-1 downto 0);
    signal tvalid : out std_ulogic;
    signal tready : out std_ulogic;
    signal tlast  : out std_ulogic;
    signal tuser  : out std_ulogic_vector(axi_stream_user_sz-1 downto 0)
   -- signal tid : out std_ulogic_vector(axi_stream_id_sz-1 downto 0);
   -- signal tdest : out std_ulogic_vector(axi_stream_dest_sz-1 downto 0);
   -- signal tkeep : out std_ulogic_vector(axi_stream_keep_sz-1 downto 0);
   -- signal tstrb : out std_ulogic_vector(axi_stream_strb_sz-1 downto 0)
    ) is
  begin
    tdata  <= i_axi_stream_m2s.data;
    tvalid <= i_axi_stream_m2s.valid;
    tready <= i_axi_stream_s2m.ready;
    tlast  <= i_axi_stream_m2s.last;
    tuser  <= i_axi_stream_m2s.user;
  -- tid <= i_axi_stream_m2s.id;
  -- tdest <= i_axi_stream_m2s.dest;
  -- tkeep <= i_axi_stream_m2s.keep;
  -- tstrb <= i_axi_stream_m2s.strb;
  end procedure connect_cocotbext_axismon;

  -- pragma translate_on

end package body sim_utils_pkg;
