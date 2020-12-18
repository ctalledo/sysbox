all: mountSyscall

mountSyscall: mount-syscall.go
	GO111MODULE="on" go build mount-syscall.go
clean:
	rm -f mount-syscall
