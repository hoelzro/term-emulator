#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>

#define FIRST_FG_COLOR 30
#define FIRST_BG_COLOR 40
#define LAST_BG_COLOR  49

// XXX should I G_EVAL methods?

// entries < FIRST_FG_COLOR are SV * (either NULL or a PV)
// entries >= FIRST_FG_COLOR are AV * (could be NULL)
static SV *ATTRIBUTE_COLOR_LOOKUP[LAST_BG_COLOR + 1];

static void
dump_table(HV *hash)
{
    HE *entry;
    hv_iterinit(hash);

    while((entry = hv_iternext(hash))) {
        I32 length;
        printf("%s\n", hv_iterkey(entry, &length));
    }
}

#define _get_member(self, name)\
    (__get_member(self, name, sizeof(name) - 1))

static SV *
__get_member(pTHX_ SV *self, const char *name, int member_length)
{
    dSP;
    SV *member;

    PUSHMARK(SP);
    XPUSHs(self);
    PUTBACK;

    call_method(name, G_SCALAR);

    SPAGAIN;

    member = POPs;

    PUTBACK;

    return member;
}

static PerlIO *
_get_pty(pTHX_ SV *self)
{
    SV *pty = _get_member(aTHX_ self, "_pty");
    return IoIFP(sv_2io(pty));
}

static SV *
_get_backend(pTHX_ SV *self)
{
    return _get_member(aTHX_ self, "backend");
}

static void
read_optional_params(PerlIO *pty, int **params_out, int *num_params_out)
{
    static int optional_params[8];
    int current_number = 0;
    int first = 1;
    char c;

    *params_out     = optional_params;
    *num_params_out = 0;

    while((c = PerlIO_getc(pty)) != -1) {
        if(isDIGIT(c)) {
            if(first) {
                current_number = c - '0';
                first          = 0;
            } else {
                current_number *= 10;
                current_number += c - '0';
            }
        } else {
            if(! first) {
                optional_params[*num_params_out] = current_number;
                if(*num_params_out < 8 - 1) {
                    (*num_params_out)++;
                }
                first = 1;
            }
            if(c != ';') {
                // XXX I'm hoping this doesn't bite me in the ass
                PerlIO_ungetc(pty, c);
                break;
            }
        }
    }
}

static void
handle_attr_or_color(pTHX_ PerlIO *pty, SV *backend, int param)
{
    const char *method_name = NULL;
    SV *attribute           = ATTRIBUTE_COLOR_LOOKUP[param];

    if(attribute == NULL) {
        // XXX handle this better?
        return;
    }

    dSP;

    PUSHMARK(SP);
    XPUSHs(backend);

    if(param < FIRST_FG_COLOR) {
        XPUSHs(attribute);
        method_name = "handle_set_attribute";
    } else if(param <= LAST_BG_COLOR) {
        AV *values = (AV *) attribute;

        XPUSHs(*av_fetch(values, 0, 0));
        XPUSHs(*av_fetch(values, 1, 0));
        XPUSHs(*av_fetch(values, 2, 0));

        if(param < FIRST_BG_COLOR) {
            method_name = "handle_set_fg_color";
        } else {
            method_name = "handle_set_bg_color";
        }
    } else {
        // XXX freak out
    }
    PUTBACK;

    call_method(method_name, G_DISCARD);
}

static void
handle_cursor_move(pTHX_ SV *backend, int dx, int dy)
{
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(backend);
    XPUSHs(sv_2mortal(newSViv(dx)));
    XPUSHs(sv_2mortal(newSViv(dy)));
    PUTBACK;

    call_method("handle_cursor_move", G_DISCARD);

    FREETMPS;
    LEAVE;
}

static void
handle_cursor_set(pTHX_ SV *backend, int x, int y)
{
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(backend);
    XPUSHs(sv_2mortal(newSViv(x)));
    XPUSHs(sv_2mortal(newSViv(y)));
    PUTBACK;

    call_method("handle_cursor_set", G_DISCARD);

    FREETMPS;
    LEAVE;
}

static void
handle_csi(pTHX_ PerlIO *pty, SV *backend)
{
    int *optional_params;
    int num_optional_params;
    char c;

    read_optional_params(pty, &optional_params, &num_optional_params);

    c = PerlIO_getc(pty);
    switch(c) {
        case 'm':
            {
                int i;
                for(i = 0; i < num_optional_params; i++) {
                    handle_attr_or_color(aTHX_ pty, backend, optional_params[i]);
                }
            }

            break;
        case 'A':
        case 'B':
        case 'C':
        case 'D':
            {
                int dx       = 0;
                int dy       = 0;

                if(c == 'A' || c == 'B') {
                    dy = (c == 'A') ? -1 : 1;
                } else if(c == 'C' || c == 'D') {
                    dx = (c == 'D') ? -1 : 1;
                }

                if(num_optional_params >= 1) {
                    dx *= optional_params[0];
                    dy *= optional_params[0];
                }

                handle_cursor_move(aTHX_ backend, dx, dy);
            }

            break;
        case 'f':
        case 'H':
            {
                int x = 0;
                int y = 0;

                if(num_optional_params >= 1) {
                    y = optional_params[0];
                    if(num_optional_params >= 2) {
                        x = optional_params[1];
                    }
                }

                handle_cursor_set(aTHX_ backend, x, y);
            }

            break;
        default:
            printf("unrecognized escape character '%c'\n", c);
    }

    // XXX free optional params?
}

static void
handle_escape_sequence(pTHX_ PerlIO *pty, SV *backend)
{
    char buffer;
    // XXX grab more than one byte at a time?
    // XXX handle error

    PerlIO_read(pty, &buffer, 1);

    switch(buffer) {
        case '[':
            handle_csi(aTHX_ pty, backend);
            break;
        default:
            // XXX handle this
            break;
    }
}

static void
handle_tab(pTHX_ SV *backend)
{
    dSP;

    PUSHMARK(SP);
    XPUSHs(backend);
    PUTBACK;

    call_method("handle_tab", G_DISCARD);
}

static void
handle_newline(pTHX_ SV *backend)
{
    dSP;

    PUSHMARK(SP);
    XPUSHs(backend);
    PUTBACK;

    call_method("handle_newline", G_DISCARD);
}

static void
handle_raw_input(pTHX_ SV *backend, const char *buffer, size_t buffer_length)
{
    dSP;
    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(backend);
    XPUSHs(sv_2mortal(newSVpvn(buffer, buffer_length)));
    PUTBACK;

    call_method("handle_raw_input", G_DISCARD);

    FREETMPS;
    LEAVE;
}

MODULE = Term::Emulator     PACKAGE = Term::Emulator

void
_handle_input(SV *self)
  CODE:
    PerlIO *pty = _get_pty(aTHX_ self);
    SV *backend = _get_backend(aTHX_ self);
    char buffer;
    int nbytes;

    // XXX grab more than one byte at a time?
    // XXX what about UTF-8?
    while((nbytes = PerlIO_read(pty, &buffer, 1)) > 0) {
        switch(buffer) {
            case '\e':
                handle_escape_sequence(aTHX_ pty, backend);
                break;
            case '\t':
                handle_tab(aTHX_ backend);
                break;
            case '\n':
                handle_newline(aTHX_ backend);
                break;
            default:
                // XXX Perl alternative to isprint? Can we use [[:print:]]?
                if(isPRINT(buffer)) {
                    handle_raw_input(aTHX_ backend, &buffer, 1);
                } else {
                    printf("%d\n", buffer);
                }
        }
    }
    if(nbytes < 0) {
        // XXX handle error
    }

BOOT:
    SV *zero  = newSViv(0);
    SV *two55 = newSViv(0xFF);
    SV *values[3];
    int i;

    ATTRIBUTE_COLOR_LOOKUP[0]  = ATTRIBUTE_COLOR_LOOKUP[22] = newSVpv("normal", 6);
    ATTRIBUTE_COLOR_LOOKUP[1]  = newSVpv("bold", 4);
    ATTRIBUTE_COLOR_LOOKUP[4]  = newSVpv("underlined", 10);
    ATTRIBUTE_COLOR_LOOKUP[5]  = newSVpv("blink", 5);
    ATTRIBUTE_COLOR_LOOKUP[7]  = newSVpv("inverse", 7);
    ATTRIBUTE_COLOR_LOOKUP[8]  = newSVpv("hidden", 6);
    ATTRIBUTE_COLOR_LOOKUP[24] = newSVpv("-underlined", 11);
    ATTRIBUTE_COLOR_LOOKUP[25] = newSVpv("-blink", 6);
    ATTRIBUTE_COLOR_LOOKUP[27] = newSVpv("-inverse", 8);
    ATTRIBUTE_COLOR_LOOKUP[28] = newSVpv("-hidden", 7);

    for(i = 0; i < 8; i++) {
        AV *av;

        values[0] = (i & 0x01) ? two55 : zero;
        values[1] = (i & 0x02) ? two55 : zero;
        values[2] = (i & 0x04) ? two55 : zero;

        av = av_make(3, values);

        ATTRIBUTE_COLOR_LOOKUP[30 + i] = ATTRIBUTE_COLOR_LOOKUP[40 + i] = (SV *) av;
    }
    // XXX 39/49 should be "original"
