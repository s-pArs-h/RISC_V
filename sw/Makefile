# Build the FPGA demo program into fpga/demo.hex (one 32-bit word per line).
PREFIX ?= riscv64-unknown-elf-
WORDS  ?= 1024          # memory size of the FPGA top level (padded with zeros)

../fpga/demo.hex: demo.elf
	$(PREFIX)objcopy -O binary $< demo.bin
	python3 -c "d=open('demo.bin','rb').read(); d+=bytes(4*$(WORDS)-len(d)); \
	open('$@','w').write(''.join(f'{int.from_bytes(d[i:i+4],\"little\"):08x}\n' for i in range(0,len(d),4)))"

demo.elf: demo.S link.ld
	$(PREFIX)gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -T link.ld $< -o $@

clean:
	rm -f demo.elf demo.bin
