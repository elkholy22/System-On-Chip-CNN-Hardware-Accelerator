# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

# Configuration file for the Sphinx documentation builder.

import os
import sys

sys.path.insert(0, os.path.abspath("../"))

# -- Project information -----------------------------------------------------

project = 'RISC-V Lab'
copyright = 'RVLab Contributors'
author = 'RVLab Contributors'

# -- General configuration ---------------------------------------------------

extensions = [
    'sphinx_rtd_theme',
    'pydesignflow.sphinx_ext',
    'flow.tools.reggen_sphinx_ext',
]

templates_path = ['_templates']

exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

# -- Options for HTML output -------------------------------------------------

html_theme = 'sphinx_rtd_theme'

html_static_path = ['_static']
