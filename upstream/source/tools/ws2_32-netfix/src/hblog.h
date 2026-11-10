/* tiny freestanding logger: no CRT, kernel32 only. Fixes are on unless HB_NETFIX=0; the log
   (Z:\tmp\hb-net.log) is written only with HB_NETLOG=1. */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stddef.h>

static int hb_on = -1;           /* fixes: -1 unknown, 0 off, 1 on */
static int hb_log_on = -1;       /* log: same */
static volatile LONG hb_lines;
static HANDLE hb_file = INVALID_HANDLE_VALUE;
static SRWLOCK hb_lock = SRWLOCK_INIT;
#define HB_MAXLINES 2000

static int hb_enabled(void)
{
    if (hb_on < 0) {
        char b[4]; DWORD le = GetLastError();
        DWORD n = GetEnvironmentVariableA("HB_NETFIX", b, sizeof(b));
        hb_on = (n == 1 && b[0] == '0') ? 0 : 1;
        n = GetEnvironmentVariableA("HB_NETLOG", b, sizeof(b));
        hb_log_on = (n == 1 && b[0] == '1') ? 1 : 0;
        SetLastError(le);
    }
    return hb_on;
}

typedef struct { char *s; char *p; char *e; } hb_buf;
static void hb_c(hb_buf *b, char c) { if (b->p < b->e) *b->p++ = c; }
static void hb_s(hb_buf *b, const char *s) { while (s && *s) hb_c(b, *s++); }
static void hb_u(hb_buf *b, unsigned long long v)
{
    char t[24]; int n = 0;
    do { t[n++] = '0' + (int)(v % 10); v /= 10; } while (v);
    while (n) hb_c(b, t[--n]);
}
static void hb_i(hb_buf *b, long long v) { if (v < 0) { hb_c(b, '-'); v = -v; } hb_u(b, (unsigned long long)v); }
static void hb_x(hb_buf *b, unsigned long long v)
{
    char t[20]; int n = 0;
    do { t[n++] = "0123456789abcdef"[v & 15]; v >>= 4; } while (v);
    hb_c(b, '0'); hb_c(b, 'x');
    while (n) hb_c(b, t[--n]);
}
static void hb_guid(hb_buf *b, const GUID *g)
{
    const unsigned char *p = (const unsigned char *)g; int i;
    const char *h = "0123456789abcdef";
    unsigned char o[16] = { p[3],p[2],p[1],p[0], p[5],p[4], p[7],p[6], p[8],p[9], p[10],p[11],p[12],p[13],p[14],p[15] };
    for (i = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10) hb_c(b, '-');
        hb_c(b, h[o[i] >> 4]); hb_c(b, h[o[i] & 15]);
    }
}
static void hb_addr(hb_buf *b, const struct sockaddr *sa, int len)
{
    if (!sa || len < 2) { hb_s(b, "(null)"); return; }
    if (sa->sa_family == AF_INET && len >= 8) {
        const unsigned char *a = (const unsigned char *)sa;
        hb_u(b, a[4]); hb_c(b, '.'); hb_u(b, a[5]); hb_c(b, '.'); hb_u(b, a[6]); hb_c(b, '.'); hb_u(b, a[7]);
        hb_c(b, ':'); hb_u(b, (a[2] << 8) | a[3]);
    } else if (sa->sa_family == AF_INET6 && len >= 24) {
        const unsigned char *a = (const unsigned char *)sa; int i;
        hb_c(b, '[');
        for (i = 0; i < 8; i++) { if (i) hb_c(b, ':'); hb_x(b, (a[8 + 2*i] << 8) | a[9 + 2*i]); }
        hb_s(b, "]:"); hb_u(b, (a[2] << 8) | a[3]);
    } else { hb_s(b, "family="); hb_u(b, sa->sa_family); }
}
/* caller module + offset */
static void hb_caller(hb_buf *b, void *ra)
{
    HMODULE m = NULL;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)ra, &m) && m) {
        char name[MAX_PATH]; DWORD n = GetModuleFileNameA(m, name, sizeof(name)), i, s = 0;
        for (i = 0; i < n; i++) if (name[i] == '\\' || name[i] == '/') s = i + 1;
        if (n < sizeof(name)) name[n] = 0;
        hb_s(b, name + s); hb_c(b, '+'); hb_x(b, (ULONG_PTR)ra - (ULONG_PTR)m);
    } else { hb_s(b, "?+"); hb_x(b, (ULONG_PTR)ra); }
}
static void hb_head(hb_buf *b, void *ra)
{
    hb_u(b, GetTickCount64()); hb_c(b, ' ');
    hb_s(b, "t"); hb_u(b, GetCurrentThreadId()); hb_c(b, ' ');
    hb_caller(b, ra); hb_c(b, ' ');
}
static void hb_emit(hb_buf *b)
{
    DWORD w;
    if (hb_log_on != 1 || hb_lines >= HB_MAXLINES) return;
    hb_c(b, '\n');
    AcquireSRWLockExclusive(&hb_lock);
    if (hb_lines < HB_MAXLINES) {
        if (hb_file == INVALID_HANDLE_VALUE)
            hb_file = CreateFileA("Z:\\tmp\\hb-net.log", FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
        if (hb_file != INVALID_HANDLE_VALUE) {
            hb_lines++;
            WriteFile(hb_file, b->s, (DWORD)(b->p - b->s), &w, NULL);
        }
    }
    ReleaseSRWLockExclusive(&hb_lock);
}
#define HB_BUF(b) char b##_raw[1024]; hb_buf b = { b##_raw, b##_raw, b##_raw + 1000 }
