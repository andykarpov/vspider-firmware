derive_clock_uncertainty
create_clock -period 14MHz -name {CLK14} [get_ports {CLK14}]
create_generated_clock -name {clk_7} -divide_by 2 -source [get_ports {CLK14}] [get_registers {clk_7}]
create_generated_clock -name {clkcpu} -divide_by 4 -source [get_ports {CLK14}] [get_registers {clkcpu}]

set_clock_groups -exclusive -group {clk_7}
set_clock_groups -exclusive -group {clkcpu}

#set_clock_groups -exclusive -group {CLK14} -group {clk_7}
#set_clock_groups -exclusive -group {CLK14} -group {clkcpu}

create_clock -period 7MHz -name N_M1 N_M1
set_false_path -from [get_ports {N_M1}] -to [all_clocks]
