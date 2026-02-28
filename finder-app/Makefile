cc := $(CROSS_COMPILE)gcc
cflags := -Wall -Werror -O2

target := writer
src := writer.c
obj := $(src:.c=.o)

all: $(target)

$(target): $(obj)
	$(cc) $(cflags) -o $@ $^

%.o: %.c
	$(cc) $(cflags) -c -o $@ $<

clean:
	rm -f $(target) $(obj)
