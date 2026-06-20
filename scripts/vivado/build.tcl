# ================================================
# Build script cho RISC-V PicoSoC trên Arty A7-100T
# ================================================

set origin_dir [file dirname [info script]]

# ====================== CÀI ĐẶT ======================
set top_module "system"

# Part của Arty A7-100T
set part "xc7a100t-csg324-1"

# ====================== TẠO PROJECT ======================
create_project -force rv_picosoc ./project -part $part

# ====================== ADD SOURCES ======================

set src_dirs [list \
    "$origin_dir" \
    "$origin_dir/../../" \
    "$origin_dir/../../picosoc" \
    "$origin_dir/../../picosoc/GIFT_COFB" \
    "$origin_dir/../../picosoc/tinyjambu" \
    "$origin_dir/../../picosoc/Xoodyak_old" \
]

foreach dir $src_dirs {
    if {[file exists $dir]} {
        # Add tất cả file .v và .sv
        set verilog_files [glob -nocomplain $dir/*.v]
        set sv_files [glob -nocomplain $dir/*.sv]
        
        if {[llength $verilog_files] > 0 || [llength $sv_files] > 0} {
            add_files -fileset sources_1 $verilog_files $sv_files
            puts "Đã add files từ: $dir"
        } else {
            puts "Không tìm thấy file source nào trong: $dir"
        }
    } else {
        puts "Không tìm thấy thư mục: $dir"
    }
}

# Add thêm file .xdc nếu có (constraints)
set xdc_files [glob -nocomplain $origin_dir/*.xdc]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 $xdc_files
    puts "Đã add constraints từ: $origin_dir"
}

# Set Top Module
set_property top $top_module [current_fileset]
puts "\nHoàn tất add sources. Top module = system"

# ====================== SYNTHESIS ======================
launch_runs synth_1 -jobs 12 -verbose
wait_on_run synth_1

open_run synth_1 -name synth_1

puts "\n========================================"
puts "Synthesis thành công!"
puts "Bây giờ bạn có thể Insert ILA:"
puts "1. Vào tab **Debug** (bên trái)"
puts "2. Nhấn **Set Up Debug**"
puts "3. Chọn các signal cần xem (clk, reset, pc, instr, ...) "
puts "4. Finish → sau đó Implement → Generate Bitstream"
puts "========================================"
