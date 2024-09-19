from tsfpga.module import BaseModule


class Module(BaseModule):
    def get_simulation_files(
        self,
            include_tests=True,
            files_include=None,
            files_avoid=None,
            **kwargs,
    ):
        """Overload"""

        return super().get_simulation_files(
            include_tests=True,
            files_include=None,
            files_avoid=[self.path / "rtl/filtering.vhd"],
            kwargs=kwargs,
        )

    def get_synthesis_files(self, files_include=None, files_avoid=None, **kwargs):
        """Overload"""

        return super().get_synthesis_files(
            files_include=None, files_avoid=[self.path / "rtl/filtering.vhd"], **kwargs
        )
