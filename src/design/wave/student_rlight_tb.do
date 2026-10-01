onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /student_rlight_tb/clk
add wave -noupdate /student_rlight_tb/rst_n
add wave -noupdate -expand /student_rlight_tb/led
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_d2h.a_ready
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_valid
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_opcode
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_param
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_size
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_source
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_address
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_mask
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_data
add wave -noupdate -expand -group {TL-UL A Channel} /student_rlight_tb/tl_h2d.a_user
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_h2d.d_ready
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_valid
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_opcode
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_param
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_size
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_source
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_sink
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_data
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_user
add wave -noupdate -expand -group {TL-UL D Channel} /student_rlight_tb/tl_d2h.d_error
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {7960899705 fs} 0}
quietly wave cursor active 1
configure wave -namecolwidth 366
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 fs} {19509 ns}
