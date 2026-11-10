/* ws2_32 wrapper: passes everything to ws2_o.dll (the renamed original). Unless HB_NETFIX=0 it
   emulates SIO_UDP_NETRESET (Wine: unsupported) and IPPROTO_IP options on dual-stack IPv6 sockets
   (macOS: EINVAL), which FH5 needs to keep its Xbox port 3074 socket. HB_NETLOG=1 logs UDP activity. */
#include "hblog.h"

#define SIO_UDP_NETRESET_ 0x9800000FUL

static HMODULE orig;
static void *P(const char *n)
{
    if (!orig) { orig = GetModuleHandleA("ws2_o.dll"); if (!orig) orig = LoadLibraryA("ws2_o.dll"); }
    return GetProcAddress(orig, n);
}
#define ORIG(var, name) static void *var##_p; if (!var##_p) var##_p = P(name)
#define CALLER __builtin_return_address(0)

/* UDP socket table */
#define NS 512
static struct { SOCKET s; int sends, recvs; } tab[NS];
static SRWLOCK tlock = SRWLOCK_INIT;
static void t_add(SOCKET s)
{
    int i, f = -1;
    AcquireSRWLockExclusive(&tlock);
    for (i = 0; i < NS; i++) { if (tab[i].s == s) { f = i; break; } if (!tab[i].s && f < 0) f = i; }
    if (f >= 0) { tab[f].s = s; tab[f].sends = tab[f].recvs = 0; }
    ReleaseSRWLockExclusive(&tlock);
}
static int t_has(SOCKET s) { int i, r = 0; if (!s || s == INVALID_SOCKET) return 0;
    AcquireSRWLockShared(&tlock); for (i = 0; i < NS; i++) if (tab[i].s == s) { r = 1; break; }
    ReleaseSRWLockShared(&tlock); return r; }
static void t_del(SOCKET s) { int i; AcquireSRWLockExclusive(&tlock);
    for (i = 0; i < NS; i++) if (tab[i].s == s) tab[i].s = 0; ReleaseSRWLockExclusive(&tlock); }
/* returns 1 if this is within the first 3 of kind (0 send, 1 recv) */
static int t_count(SOCKET s, int kind) { int i, r = 0;
    AcquireSRWLockExclusive(&tlock);
    for (i = 0; i < NS; i++) if (tab[i].s == s) { int *c = kind ? &tab[i].recvs : &tab[i].sends; r = (*c)++ < 3; break; }
    ReleaseSRWLockExclusive(&tlock); return r; }

static void ret_err(hb_buf *b, long long r, DWORD err) { hb_s(b, " = "); hb_i(b, r); hb_s(b, " err="); hb_u(b, err); }

/* ---- socket creation ---- */
static void created(SOCKET s, int af, int type, int proto, const char *fn, void *ra, DWORD err)
{
    HB_BUF(b);
    if (!(type == SOCK_DGRAM || (type == 0 && proto == IPPROTO_UDP))) return;
    if (s != INVALID_SOCKET) t_add(s);
    hb_head(&b, ra); hb_s(&b, fn); hb_s(&b, " af="); hb_i(&b, af); hb_s(&b, " type="); hb_i(&b, type);
    hb_s(&b, " proto="); hb_i(&b, proto); hb_s(&b, " -> h="); hb_u(&b, s); hb_s(&b, " err="); hb_u(&b, err);
    hb_emit(&b);
}
SOCKET WSAAPI wrap_socket(int af, int type, int proto)
{
    ORIG(f, "socket"); SOCKET s = ((SOCKET (WSAAPI *)(int,int,int))f_p)(af, type, proto);
    if (hb_enabled()) { DWORD e = GetLastError(); created(s, af, type, proto, "socket", CALLER, e); SetLastError(e); }
    return s;
}
SOCKET WSAAPI wrap_WSASocketW(int af, int type, int proto, LPWSAPROTOCOL_INFOW pi, GROUP g, DWORD fl)
{
    ORIG(f, "WSASocketW"); SOCKET s = ((SOCKET (WSAAPI *)(int,int,int,LPWSAPROTOCOL_INFOW,GROUP,DWORD))f_p)(af, type, proto, pi, g, fl);
    if (hb_enabled()) { DWORD e = GetLastError(); created(s, af, type, proto, "WSASocketW", CALLER, e); SetLastError(e); }
    return s;
}
SOCKET WSAAPI wrap_WSASocketA(int af, int type, int proto, LPWSAPROTOCOL_INFOA pi, GROUP g, DWORD fl)
{
    ORIG(f, "WSASocketA"); SOCKET s = ((SOCKET (WSAAPI *)(int,int,int,LPWSAPROTOCOL_INFOA,GROUP,DWORD))f_p)(af, type, proto, pi, g, fl);
    if (hb_enabled()) { DWORD e = GetLastError(); created(s, af, type, proto, "WSASocketA", CALLER, e); SetLastError(e); }
    return s;
}

/* ---- bind / connect ---- */
int WSAAPI wrap_bind(SOCKET s, const struct sockaddr *a, int len)
{
    ORIG(f, "bind"); int r = ((int (WSAAPI *)(SOCKET,const struct sockaddr*,int))f_p)(s, a, len);
    if (hb_enabled() && t_has(s)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "bind h="); hb_u(&b, s); hb_c(&b, ' '); hb_addr(&b, a, len); ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}
int WSAAPI wrap_connect(SOCKET s, const struct sockaddr *a, int len)
{
    ORIG(f, "connect"); int r = ((int (WSAAPI *)(SOCKET,const struct sockaddr*,int))f_p)(s, a, len);
    if (hb_enabled() && t_has(s)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "connect h="); hb_u(&b, s); hb_c(&b, ' '); hb_addr(&b, a, len); ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}
int WSAAPI wrap_WSAConnect(SOCKET s, const struct sockaddr *a, int len, LPWSABUF ci, LPWSABUF cd, LPQOS q1, LPQOS q2)
{
    ORIG(f, "WSAConnect"); int r = ((int (WSAAPI *)(SOCKET,const struct sockaddr*,int,LPWSABUF,LPWSABUF,LPQOS,LPQOS))f_p)(s, a, len, ci, cd, q1, q2);
    if (hb_enabled() && t_has(s)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "WSAConnect h="); hb_u(&b, s); hb_c(&b, ' '); hb_addr(&b, a, len); ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}

/* ---- send / recv ---- */
int WSAAPI wrap_sendto(SOCKET s, const char *buf, int len, int fl, const struct sockaddr *a, int alen)
{
    ORIG(f, "sendto"); int r = ((int (WSAAPI *)(SOCKET,const char*,int,int,const struct sockaddr*,int))f_p)(s, buf, len, fl, a, alen);
    if (hb_enabled() && t_has(s) && t_count(s, 0)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "sendto h="); hb_u(&b, s); hb_s(&b, " to="); hb_addr(&b, a, alen);
        hb_s(&b, " len="); hb_i(&b, len); ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}
int WSAAPI wrap_WSASendTo(SOCKET s, LPWSABUF bufs, DWORD nb, LPDWORD sent, DWORD fl, const struct sockaddr *a, int alen, LPWSAOVERLAPPED o, LPWSAOVERLAPPED_COMPLETION_ROUTINE c)
{
    ORIG(f, "WSASendTo"); int r = ((int (WSAAPI *)(SOCKET,LPWSABUF,DWORD,LPDWORD,DWORD,const struct sockaddr*,int,LPWSAOVERLAPPED,LPWSAOVERLAPPED_COMPLETION_ROUTINE))f_p)(s, bufs, nb, sent, fl, a, alen, o, c);
    if (hb_enabled() && t_has(s) && t_count(s, 0)) { DWORD e = GetLastError(), i, tot = 0; HB_BUF(b);
        for (i = 0; bufs && i < nb; i++) tot += bufs[i].len;
        hb_head(&b, CALLER); hb_s(&b, "WSASendTo h="); hb_u(&b, s); hb_s(&b, " to="); hb_addr(&b, a, alen);
        hb_s(&b, " len="); hb_u(&b, tot); hb_s(&b, o ? " overlapped" : ""); ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}
int WSAAPI wrap_recvfrom(SOCKET s, char *buf, int len, int fl, struct sockaddr *a, int *alen)
{
    ORIG(f, "recvfrom"); int r = ((int (WSAAPI *)(SOCKET,char*,int,int,struct sockaddr*,int*))f_p)(s, buf, len, fl, a, alen);
    if (hb_enabled() && t_has(s) && t_count(s, 1)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "recvfrom h="); hb_u(&b, s); hb_s(&b, " buflen="); hb_i(&b, len);
        if (r >= 0 && a && alen) { hb_s(&b, " from="); hb_addr(&b, a, *alen); }
        ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}
int WSAAPI wrap_WSARecvFrom(SOCKET s, LPWSABUF bufs, DWORD nb, LPDWORD got, LPDWORD fl, struct sockaddr *a, LPINT alen, LPWSAOVERLAPPED o, LPWSAOVERLAPPED_COMPLETION_ROUTINE c)
{
    ORIG(f, "WSARecvFrom"); int r = ((int (WSAAPI *)(SOCKET,LPWSABUF,DWORD,LPDWORD,LPDWORD,struct sockaddr*,LPINT,LPWSAOVERLAPPED,LPWSAOVERLAPPED_COMPLETION_ROUTINE))f_p)(s, bufs, nb, got, fl, a, alen, o, c);
    if (hb_enabled() && t_has(s) && t_count(s, 1)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "WSARecvFrom h="); hb_u(&b, s); hb_s(&b, o ? " overlapped" : "");
        if (r == 0 && got) { hb_s(&b, " got="); hb_u(&b, *got); }
        ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}

/* ---- ioctl / sockopt / misc ---- */
int WSAAPI wrap_WSAIoctl(SOCKET s, DWORD code, LPVOID in, DWORD inl, LPVOID out, DWORD outl, LPDWORD ret, LPWSAOVERLAPPED o, LPWSAOVERLAPPED_COMPLETION_ROUTINE c)
{
    ORIG(f, "WSAIoctl");
    int r = ((int (WSAAPI *)(SOCKET,DWORD,LPVOID,DWORD,LPVOID,DWORD,LPDWORD,LPWSAOVERLAPPED,LPWSAOVERLAPPED_COMPLETION_ROUTINE))f_p)(s, code, in, inl, out, outl, ret, o, c);
    if (hb_enabled() && t_has(s)) {
        DWORD e = GetLastError(); HB_BUF(b); int fixed = 0; int orr = r;
        if (code == SIO_UDP_NETRESET_ && r != 0) { r = 0; e = 0; fixed = 1; if (ret) *ret = 0; }
        hb_head(&b, CALLER); hb_s(&b, "WSAIoctl h="); hb_u(&b, s); hb_s(&b, " code="); hb_x(&b, code);
        hb_s(&b, " inlen="); hb_u(&b, inl);
        if (in && inl >= 4) { hb_s(&b, " in0="); hb_x(&b, *(DWORD *)in); }
        if (fixed) { hb_s(&b, " ORIG="); hb_i(&b, orr); hb_s(&b, " (wrapper forced success)"); }
        ret_err(&b, r, e); hb_emit(&b); SetLastError(e);
    }
    return r;
}
int WSAAPI wrap_setsockopt(SOCKET s, int lvl, int opt, const char *val, int len)
{
    ORIG(f, "setsockopt"); int r = ((int (WSAAPI *)(SOCKET,int,int,const char*,int))f_p)(s, lvl, opt, val, len);
    int orr = r, alt = -2;
    /* Windows accepts IPPROTO_IP options on a dual-stack AF_INET6 socket; macOS (and so Wine) answers
       WSAEINVAL, and FH5 then closes its Xbox port 3074 socket and stays offline. Apply the IPv6
       equivalent (IP_TTL -> IPV6_UNICAST_HOPS, multicast TTL/loop, TOS -> TCLASS) and report success. */
    if (r != 0 && lvl == 0 /* IPPROTO_IP */ && hb_enabled()) {
        DWORD e0 = GetLastError();
        if (e0 == WSAEINVAL || e0 == WSAENOPROTOOPT) {
            int o6 = opt == 4 ? 4 : opt == 10 ? 10 : opt == 11 ? 11 : opt == 3 ? 39 : -1;
            if (o6 >= 0) alt = ((int (WSAAPI *)(SOCKET,int,int,const char*,int))f_p)(s, 41 /* IPPROTO_IPV6 */, o6, val, len);
            r = 0; SetLastError(0);
        } else SetLastError(e0);
    }
    if (hb_enabled() && t_has(s)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "setsockopt h="); hb_u(&b, s); hb_s(&b, " level="); hb_i(&b, lvl); hb_s(&b, " opt="); hb_i(&b, opt);
        hb_s(&b, " len="); hb_i(&b, len);
        if (val && len >= 4) { hb_s(&b, " val0="); hb_x(&b, *(DWORD *)val); } else if (val && len == 1) { hb_s(&b, " val0="); hb_x(&b, *(unsigned char *)val); }
        if (orr != r) { hb_s(&b, " ORIG="); hb_i(&b, orr); hb_s(&b, " ipv6alt="); hb_i(&b, alt); hb_s(&b, " (wrapper forced success)"); }
        ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}
int WSAAPI wrap_getsockname(SOCKET s, struct sockaddr *a, int *alen)
{
    ORIG(f, "getsockname"); int r = ((int (WSAAPI *)(SOCKET,struct sockaddr*,int*))f_p)(s, a, alen);
    if (hb_enabled() && t_has(s)) { DWORD e = GetLastError(); HB_BUF(b);
        hb_head(&b, CALLER); hb_s(&b, "getsockname h="); hb_u(&b, s);
        if (r == 0 && a && alen) { hb_c(&b, ' '); hb_addr(&b, a, *alen); }
        ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}
int WSAAPI wrap_closesocket(SOCKET s)
{
    ORIG(f, "closesocket"); int u = hb_enabled() && t_has(s); DWORD e;
    int r = ((int (WSAAPI *)(SOCKET))f_p)(s);
    if (u) { HB_BUF(b); e = GetLastError(); t_del(s);
        hb_head(&b, CALLER); hb_s(&b, "closesocket h="); hb_u(&b, s); ret_err(&b, r, e); hb_emit(&b); SetLastError(e); }
    return r;
}

BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID res) { return TRUE; }
