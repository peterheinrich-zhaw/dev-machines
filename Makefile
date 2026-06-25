all:
	sh aarch64_osx_run.sh
firstboot:
	sh aarch64_osx_run.sh -nographic
clean:
	rm -rf cache* config* scratch* *.log build
mrproper:
	rm -rf cache* config* scratch* *.log build download

