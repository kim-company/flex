export BINDIR ?= $(abspath bin)
BINS := authorise
TOOLS := $(addprefix $(BINDIR)/admin/, $(BINS))

all: $(TOOLS)

$(BINDIR): ; mkdir -p $@
$(BINDIR)/admin/%: ; $(MAKE) -C flexi $@
