# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

import hjson
from pathlib import Path
from .reggen import gen_ctheader, gen_html, gen_rtl, validate

def run_reggen(input_hjson_fn: Path, output_pkg_sv: Path = None, output_top_sv: Path = None, output_header: Path = None, output_html: Path = None):
    with open(input_hjson_fn) as f:
        obj = hjson.load(f) #, use_decimal=True, object_pairs_hook=validate.checking_dict)
    
    params = []
    if (retval := validate.validate(obj, params=params)) != 0:
        raise Exception(f"reggen validate.validate returned {retval}.")

    src_lic = None
    src_copy = ''

    if output_top_sv and output_pkg_sv:
        gen_rtl.gen_rtl(obj, output_pkg_sv, output_top_sv)

    if output_header:
        with open(output_header, 'w') as f:
            #gen_cheader.gen_cdefines(obj, f, src_lic, src_copy)
            gen_ctheader.gen_cdefines(obj, f, src_lic, src_copy)

    if output_html:
        with open(output_html, 'w') as f:
            gen_html.gen_html(obj, f)
