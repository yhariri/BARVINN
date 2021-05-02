# BARVINN: A Barrel RISC-V Neural Network Accelerator:

![alt text](https://github.com/hossein1387/Accelerator/blob/documentation/docs/_static/BARVINN_LOGO_2_DARK.png)

## How to Use:
    
    git clone https://github.com/obilaniu/MVU.git
    git clone https://github.com/hossein1387/pito_riscv.git
    cd pito_riscv
    git checkout csr
    cd verification


    ./do_test.py -f files.f -t accel_tester -s xilinx -l libs.f -m vlogmacros.f


## Build Documentation:

    cd docs
    python pip -r install requirements
    make html

Then, you can open `./docs/_build/html/index.html` file.
