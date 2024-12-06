-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
-- Copyright (c) DESY
--
-- This file is part of the hdl-modules project, a collection of reusable, high-quality,
-- peer-reviewed VHDL building blocks.
-- https://hdl-modules.com
-- https://github.com/hdl-modules/hdl-modules
-- -------------------------------------------------------------------------------------------------
-- Modified file is part of the corel project
-- https://gitlab.desy.de/ultrasat-camera/corel
--
-- Changes:
-- * added async reset logic (can be left unconnected)
-- * added axi write strobe handling (big or little endian)
-- * regs_up_valid, regs_up_ready, regs_up_slverr
-- * regs_down_slverr, regs_down_strb
-------------------------------------------------------------------------------
-- Generic, parameterizable, register file for AXI-Lite register buses.
-- Is parameterizable via a generic that sets the list of registers, with their modes and their
-- default values.
--
-- Will respond with ``SLVERR`` on the ``R`` channel when attempting to read a register that
--
-- 1. Does not exists (``ARADDR`` out of range), or
-- 2. Is not of a register type that can be read by the bus (e.g. write only).
--
-- Similarly, it will respond with ``SLVERR`` on the ``B`` channel when attempting to write a
-- register that
--
-- 1. Does not exists (``AWADDR`` out of range), or
-- 2. Is not of a register type that can be written by the bus (e.g. read only).
--
-- Both cases are handled cleanly without stalling or hanging the AXI-Lite bus.
--
-- The ``regs`` and ``default_values`` generics are designed to get their values
-- from a package generated by the ``hdl-registers`` VHDL generator:
-- :py:class:`VhdlRegisterPackageGenerator
-- <hdl_registers.generator.vhdl.register_package.VhdlRegisterPackageGenerator>`.
-- The values can be constructed by hand as well, of course.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library common;
use common.addr_pkg.all;

library axi;
use axi.axi_pkg.all;

library axi_lite;
use axi_lite.axi_lite_pkg.all;

use work.reg_file_pkg.all;


entity axi_lite_reg_file is
  generic (
    regs           : reg_definition_vec_t;
    default_values : reg_vec_t(regs'range) := (others => (others => '0'));
    use_wstrb      : boolean               := false;
    -- If 'big' wstrb(0) qualifies the most significant byte.  If 'small', the
    -- least significant.
    big_endian     : boolean               := true  -- true for big, false for little
    );
  port (
    rst_n            : in  std_ulogic                    := '1';
    clk              : in  std_ulogic;
    --# {{}}
    --# Register control bus
    axi_lite_m2s     : in  axi_lite_m2s_t;
    axi_lite_s2m     : out axi_lite_s2m_t                := axi_lite_s2m_init;
    --# {{}}
    -- Register values
    regs_up          : in  reg_vec_t(regs'range)         := default_values;
    regs_up_valid    : in  std_ulogic_vector(regs'range) := (others => '1');
    regs_up_ready    : out std_ulogic_vector(regs'range) := (others => '0');
    regs_up_slverr   : in  std_ulogic_vector(regs'range) := (others => '0');
    regs_down        : out reg_vec_t(regs'range)         := default_values;
    regs_down_slverr : in  std_ulogic_vector(regs'range) := (others => '0');
    --# {{}}
    -- Each bit is pulsed for one cycle when the corresponding register is read/written.
    -- For read, the bit is asserted the exact same cycle as the AXI-Lite R transaction occurs.
    -- For write, the bit is asserted the cycle after the AXI-Lite W transaction occurs, so that
    -- 'regs_down' is updated with the new value.
    reg_was_read     : out std_ulogic_vector(regs'range) := (others => '0');
    reg_was_written  : out std_ulogic_vector(regs'range) := (others => '0');
    reg_down_strb    : out std_ulogic_vector(axi_lite_w_strb_sz-1 downto 0)
    );
end entity;

architecture a of axi_lite_reg_file is

  constant addr_and_mask_vec : addr_and_mask_vec_t := to_addr_and_mask_vec(regs);

  signal reg_values : reg_vec_t(regs'range) := default_values;

  constant invalid_addr : natural := regs'length;
  subtype decoded_idx_t is natural range 0 to invalid_addr;

begin

  read_block : block
    type read_state_t is (ar, r);
    signal read_state : read_state_t := ar;
  begin

    read_process : process(clk, rst_n)
      variable v_data        : reg_t;
      variable v_read_idx    : integer range regs'range;
      variable v_decoded_idx : decoded_idx_t;

      -- An address transaction has occured and the address points to a valid
      -- read register
      function is_valid_read_address (
        idx : integer) return boolean is
      begin
        return (
          idx /= invalid_addr and
          is_read_type(regs(idx).reg_type));
      end function;

      -- purpose: set axi read data and read response. If address is valid
      -- response is okay, else slverr.
      procedure set_axi_response (
        idx  : natural;
        data : reg_t
        ) is
      begin
        if is_valid_read_address(idx) and regs_up_slverr(idx) = '0' then
          axi_lite_s2m.read.r.resp <= axi_resp_okay;
          axi_lite_s2m.read.r.data(data'range) <= data;
        else
          axi_lite_s2m.read.r.resp <= axi_resp_slverr;
          axi_lite_s2m.read.r.data <= (others => '-');
        end if;
      end procedure set_axi_response;

    begin
      if not rst_n then
        axi_lite_s2m.read <= axi_lite_read_s2m_init;
        read_state        <= ar;

        v_data        := (others => '-');
        v_decoded_idx := invalid_addr;
        v_read_idx    := 0;

        v_decoded_idx := invalid_addr;
        regs_up_ready <= (others => '0');
        reg_was_read  <= (others => '0');
      elsif rising_edge(clk) then

        axi_lite_s2m.read <= axi_lite_read_s2m_init;

        reg_was_read <= (others => '0');
        v_data       := (others => '-');

        case read_state is
          when ar =>
            v_read_idx    := 0;
            v_decoded_idx := invalid_addr;

            axi_lite_s2m.read.ar.ready <= '1';
            regs_up_ready              <= (others => '0');

            if axi_lite_m2s.read.ar.valid and axi_lite_s2m.read.ar.ready then
              axi_lite_s2m.read.ar.ready <= '0';
              v_decoded_idx              := decode(axi_lite_m2s.read.ar.addr, addr_and_mask_vec);
              if v_decoded_idx /= invalid_addr then
                v_read_idx := v_decoded_idx;
              end if;

              read_state <= r;
            end if;

          when r =>
            axi_lite_s2m.read.r.valid <= '1';
            regs_up_ready(v_read_idx) <= '1';

            if is_fabric_gives_value_type(regs(v_read_idx).reg_type) then
              if not regs_up_valid(v_read_idx) then
                -- hold off transaction if regs_up_valid(idx) is
                -- deasserted.
                axi_lite_s2m.read.r.valid <= '0';
              else
                v_data := regs_up(v_read_idx);
              end if;
            else
              v_data := regs_down(v_read_idx);
            end if;

            set_axi_response(v_read_idx, v_data);

            if axi_lite_m2s.read.r.ready and axi_lite_s2m.read.r.valid then
              axi_lite_s2m.read.r.valid  <= '0';
              axi_lite_s2m.read.ar.ready <= '1';
              regs_up_ready              <= (others => '0');

              if is_valid_read_address(v_read_idx) then
                reg_was_read(v_read_idx) <= '1';
              end if;

              read_state <= ar;
            end if;
        end case;

      end if;
    end process;
  end block;


  write_block : block
    type write_state_t is (aw, w, b);
    signal write_state : write_state_t := aw;
  begin

    write_process : process(clk, rst_n)
      variable v_byte_idx    : integer range 0 to axi_lite_w_strb_sz-1;
      variable v_decoded_idx : decoded_idx_t;
      variable v_write_idx   : integer range regs'range;
      variable v_data        : reg_t;

      -- An address transaction has occured and the address points to a valid
      -- write register
      function is_valid_write_address (
        idx : integer) return boolean is
      begin
        return idx /= invalid_addr and
          is_write_type(regs(idx).reg_type);
      end function;

      -- purpose: set axi write response. If address is valid response is okay,
      -- else slverr.
      procedure set_axi_response (
        idx : natural
        ) is
      begin
        if is_valid_write_address(idx) and regs_down_slverr(idx) = '0' then
          axi_lite_s2m.write.b.resp <= axi_resp_okay;
        else
          axi_lite_s2m.write.b.resp <= axi_resp_slverr;
        end if;
      end procedure set_axi_response;

    begin
      if not rst_n then
        axi_lite_s2m.write <= axi_lite_write_s2m_init;

        regs_down <= default_values;

        write_state   <= aw;
        v_decoded_idx := invalid_addr;
        v_write_idx   := 0;
        v_data        := (others => '-');

        regs_down     <= default_values;
        reg_down_strb <= (others => '0');
      elsif rising_edge(clk) then

        axi_lite_s2m.write <= axi_lite_write_s2m_init;
        reg_down_strb      <= (others => '0');
        reg_was_written    <= (others => '0');
        v_data             := (others => '-');

        -- if valid_write_address then
        --   axi_lite_s2m.write.b.resp <= axi_resp_okay;
        -- else
        --   axi_lite_s2m.write.b.resp <= axi_resp_slverr;
        -- end if;

        -- clear write pulse registers
        for idx in regs'range loop
          if is_write_pulse_type(regs(idx).reg_type) then
            regs_down(idx) <= default_values(idx);
          end if;
        end loop;

        case write_state is
          when aw =>
            v_write_idx   := 0;
            v_decoded_idx := invalid_addr;

            axi_lite_s2m.write.aw.ready <= '1';
            if axi_lite_m2s.write.aw.valid and axi_lite_s2m.write.aw.ready then
              axi_lite_s2m.write.aw.ready <= '0';

              v_decoded_idx := decode(axi_lite_m2s.write.aw.addr, addr_and_mask_vec);
              if v_decoded_idx /= invalid_addr then
                v_write_idx := v_decoded_idx;
              end if;

              axi_lite_s2m.write.w.ready <= '1';
              write_state                <= w;
            end if;

          when w =>
            axi_lite_s2m.write.w.ready <= '1';
            if axi_lite_m2s.write.w.valid and axi_lite_s2m.write.w.ready then
              axi_lite_s2m.write.w.ready <= '0';

              if is_valid_write_address(v_write_idx) then

                if use_wstrb then
                  v_data := regs_down(v_write_idx);
                  for i in axi_lite_m2s.write.w.strb'range loop
                    if axi_lite_m2s.write.w.strb(i) then

                      if not big_endian then
                        v_byte_idx := i;
                      else
                        v_byte_idx := axi_lite_w_strb_sz-i-1;
                      end if;

                      v_data(
                        (v_byte_idx+1)*8-1 downto v_byte_idx*8) := axi_lite_m2s.write.w.data((v_byte_idx+1)*8-1 downto v_byte_idx*8);
                    end if;
                  end loop;

                else
                  -- not using write strobe => write all bytes.
                  v_data := axi_lite_m2s.write.w.data(v_data'range);
                end if;

                regs_down(v_write_idx)      <= axi_lite_m2s.write.w.data(regs_down(0)'range);
                reg_was_written(v_write_idx) <= '1';
              end if;

              set_axi_response(v_write_idx);
              axi_lite_s2m.write.b.valid <= '1';
              write_state                <= b;
              reg_down_strb                <= axi_lite_m2s.write.w.strb;
            end if;

          when b =>
            set_axi_response(v_write_idx);
            axi_lite_s2m.write.b.valid <= '1';
            if axi_lite_m2s.write.b.ready and axi_lite_s2m.write.b.valid then
              axi_lite_s2m.write.aw.ready <= '1';
              axi_lite_s2m.write.b.valid  <= '0';
              axi_lite_s2m.write.b.resp <= axi_resp_slverr;

              write_state <= aw;
            end if;
        end case;
      end if;
    end process;
  end block;

end architecture;
