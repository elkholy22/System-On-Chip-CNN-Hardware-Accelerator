# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

from pydesignflow import Block, task, Result
from .tools.tlgen_wrapper import run_tlgen
import re

class XbarGenerator(Block):
    """Crossbar switch generator using OpenTitan's tlgen"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def setup(self):
        self.src_dir = self.flow.base_dir / "src"
        self.design_dir = self.src_dir / "design"

    def find_xbars(self):
        for hjson_input_fn in (self.design_dir / "tlgen").iterdir():
            m = re.match(r"xbar_(.*).hjson", hjson_input_fn.name)
            if not m:
                continue
            name = m.group(1)
            yield name, hjson_input_fn

    @task(hidden=True)
    def generate(self, cwd):
        """Generate SystemVerilog sources"""
        r = Result()
        r.rtl_srcs = []
        for name, hjson_input_fn in self.find_xbars():
            print(f"Generating TL-UL crossbar switch xbar_{name}...")
            pkg_sv = cwd / f"tl_{name}_pkg.sv"
            rtl_sv = cwd / f"xbar_{name}.sv"
            run_tlgen(hjson_input_fn, rtl_sv, pkg_sv)

            r.rtl_srcs += [pkg_sv, rtl_sv]
        return r
