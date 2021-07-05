export BINDIR ?= $(abspath bin)

SCRIPTNAMES := keygen
BINNAMES := authorise
BINS := $(addprefix $(BINDIR)/admin/, $(BINNAMES))
SCRIPTS := $(addprefix $(BINDIR)/aux/, $(SCRIPTNAMES))

all: $(BINS) $(SCRIPTS)
clean: ; rm -rf $(BINDIR)

$(BINS): | $(BINDIR)/admin
$(SCRIPTS): | $(BINDIR)/aux
$(BINDIR)/aux: ; mkdir -p $@
$(BINDIR)/admin: ; mkdir -p $@

$(BINDIR)/aux/%: ; cp flexi/aux/$* $@
$(BINDIR)/admin/%: ; $(MAKE) -C flexi $@
