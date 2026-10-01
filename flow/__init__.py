# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

from pydesignflow import Flow

from .rvlab_fpga_top import RvlabFpgaTop
from .system_tb import SystemTb
from .xbar import XbarGenerator
from .sw import Program, Libsys
from .simlibs_questa import SimlibsQuesta
from .module_tb import ModuleTb
from .sources import Sources
from .reggen import RegisterGenerator
from .ddr3_model import Ddr3Model

flow = Flow()

# Software
# --------

sw_dirs = [
    "monitor",
    "minimal",
    "test_sim_ddr",
    "test_rvlab",
    "coremark",
    "test_irq",
    "rlight",
    "dma",
    "cnn",
    "cnn_uart",
    "cnn_cpu",
    "cnn_cpu_uart",
    "project",
    "hal_tests",
]

flow['libsys'] = Libsys(dependency_map={'reggen': 'reggen'})
for sw_dir in sw_dirs:
    flow[f'sw_{sw_dir}'] = Program(sw_dir, dependency_map={
        'libsys':'libsys', 'ref':'sw_test_rvlab', 'reggen': 'reggen'})

# Hardware
# --------

flow['xbar'] = XbarGenerator()
flow['reggen'] = RegisterGenerator()
flow['simlibs_questa'] = SimlibsQuesta()
flow['ddr3_model'] = Ddr3Model()
flow['srcs'] = Sources(dependency_map={
    'xbar': 'xbar',
    'reggen': 'reggen',
    'swinit': 'sw_test_rvlab',
    'ddr3_model': 'ddr3_model',
})

flow['rvlab_fpga_top'] = RvlabFpgaTop(dependency_map={'srcs':'srcs'})


# Testbenches
# -----------

module_tbs = [
    "student_rlight_tb",
    "student_tlul_mux_tb",
    "student_systolic_array_tb",
    "student_argmax_tb",
    "student_feed_array_tb",
    "student_cnn_tb",
    "student_cnn_cdc_tb",
    "conv1_verif_tb",
    "conv2_verif_tb",
    "fc1_verif_tb",
    "student_uart_core_tb",
    "student_uart_tb",
    "student_ws_conv1_engine_tb",
    "student_ws_conv2_engine_tb",
    "student_ws_conv2_tb",
    "student_relu_pool_tb",
    "student_pe_db_tb",
    "student_im2col_tb",
    "student_image_bram_tb",
    "student_act_buffer_tb",
    "student_weight_bram_tb",
    "student_ws_accum_tb",
    "student_controller_fsm_tb",
    "student_oled_gpio_tb",
    "student_irq_ctrl_tb",
    "student_dma_tb",
]

for name in module_tbs:
    flow[name] = ModuleTb(name, dependency_map={
        'srcs':'srcs',
        'simlibs_questa':'simlibs_questa',
    })

for sw_dir in sw_dirs:
    flow[f'systb_{sw_dir}'] = SystemTb(dependency_map={
        'srcs':'srcs',
        'sw':f'sw_{sw_dir}',
        'simlibs_questa':'simlibs_questa',
        'fpga_top':'rvlab_fpga_top',
    })
