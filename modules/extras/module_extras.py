#!/usr/bin/env python3

from tsfpga.module import BaseModule


class Module(BaseModule):
    def get_simulation_files(
        self, include_tests=True, files_include=None, files_avoid=None, **kwargs
    ):
        return super().get_simulation_files(
            include_tests=True,
            files_include=None,
            files_avoid=list(self.path.glob("test/*")),
            **kwargs
        )

    def get_synthesis_files(self, files_include=None, files_avoid=None, **kwargs):
        return super().get_synthesis_files(
            files_include=None,
            files_avoid=[
                self.path / "rtl/timing_ops_xilinx.vhd",
                self.path / "rtl/gray_code.vhd",
            ],
            **kwargs
        )
