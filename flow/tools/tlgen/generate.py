# Copyright lowRISC contributors.
# SPDX-FileCopyrightText: 2024 RVLab Contributors
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Modified by RVLab Contributors.

import logging as log
from mako import exceptions
from mako.template import Template
import importlib.resources
from pathlib import Path

from .item import NodeType
from .xbar import Xbar



def generate(xbar):  #xbar: Xbar -> str
    """generate uses elaborated model then creates top level Xbar module
    with prefix.
    """

    pkg = importlib.resources.files(__package__)
    xbar_rtl_tpl = Template((pkg / 'xbar.rtl.sv.tpl').read_text())
    xbar_pkg_tpl = Template((pkg / 'xbar.pkg.sv.tpl').read_text())
    xbar_core_tpl = Template((pkg / 'xbar.core.tpl').read_text())

    try:
        out_rtl = xbar_rtl_tpl.render(xbar=xbar, ntype=NodeType)
        out_pkg = xbar_pkg_tpl.render(xbar=xbar)
        out_core = xbar_core_tpl.render(xbar=xbar, ntype=NodeType)
    except:
        log.error(exceptions.text_error_template().render())

    results = []
    results.append(("rtl/autogen/xbar_%s.sv" % (xbar.name), out_rtl))
    results.append(("rtl/autogen/tl_%s_pkg.sv" % (xbar.name), out_pkg))
    results.append(("xbar_%s.core" % (xbar.name), out_core))
    
    return results
