cc ?= gcc
cflags ?= -wall -werror -o2
ldflags ?=

target = writer
obj = writer.o

all: $(target)

$(target): $(obj)
	$(cc) $(ldflags) -o $@ $^

%.o: %.c
	$(cc) $(cflags) -c -o $@ $<

clean:
	rm -f $(target) $(obj)

.PHONY: all clean
