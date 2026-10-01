# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

from pydesignflow import Block, task, Result
import re
from .tools.reggen_wrapper import run_reggen

class RegisterGenerator(Block):
    """Register generator using OpenTitan's reggen"""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def setup(self):
        self.src_dir = self.flow.base_dir / "src"
        self.design_dir = self.src_dir / "design"
    
    def find_reggens(self):
        for input_hjson_fn in (self.design_dir / "reggen").iterdir():
            m = re.match(r"(.*)\.hjson", input_hjson_fn.name)
            if not m:
                continue
            name = m.group(1)
            yield name, input_hjson_fn

    @task()
    def generate(self, cwd):
        """Generate SystemVerilog + C headers"""
        r = Result()
        r.c_include_dir = cwd / 'include'
        header_dir = r.c_include_dir / 'reggen'
        header_dir.mkdir(parents=True)
        r.rtl_srcs = []

        outdir_rtl = cwd / 'rtl'
        outdir_rtl.mkdir()
        outdir_html = cwd / 'html'
        outdir_html.mkdir()

        for name, input_hjson_fn in self.find_reggens():
            print(f"Generating TL-UL register module and C headers for {name}...")

            top_sv = outdir_rtl / f"{name}_reg_top.sv"
            pkg_sv = outdir_rtl / f"{name}_reg_pkg.sv"
            header = header_dir / f'{name}.h'
            html = outdir_html / f'{name}.html'

            run_reggen(input_hjson_fn, pkg_sv, top_sv, header, html)
            r.rtl_srcs += [pkg_sv, top_sv]
            
        return r
