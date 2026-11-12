/*
 * Logging stand-in for Windows' hid.dll, for recording what AULA's F75 driver
 * (OemDrv.exe, 32-bit) sends to the keyboard.
 *
 * Put this file, named hid.dll, next to OemDrv.exe. Windows loads a DLL from the
 * application's folder before System32, so the driver calls these functions; each
 * one passes the call to the real hid.dll unchanged. HidD_SetFeature and
 * HidD_GetFeature also append the report bytes to aula-hid-log.txt on the Desktop,
 * and HidD_GetAttributes records which USB device each handle belongs to.
 *
 * It only reads what the driver already sends; it never changes or adds a report.
 * Delete hid.dll from the driver's folder to remove it.
 */

#include <windows.h>

typedef BOOLEAN(WINAPI *SetGetFeatureFn)(HANDLE, PVOID, ULONG);
typedef BOOLEAN(WINAPI *GetAttributesFn)(HANDLE, PVOID);
typedef void(WINAPI *GetHidGuidFn)(LPGUID);
typedef BOOLEAN(WINAPI *GetPreparsedDataFn)(HANDLE, PVOID *);
typedef BOOLEAN(WINAPI *FreePreparsedDataFn)(PVOID);
typedef LONG(WINAPI *GetCapsFn)(PVOID, PVOID);
typedef LONG(WINAPI *GetSpecificCapsFn)(ULONG, ULONG, ULONG, ULONG, PVOID, PUSHORT, PVOID);

static HMODULE real;
static SetGetFeatureFn realSetFeature, realGetFeature;
static GetAttributesFn realGetAttributes;
static GetHidGuidFn realGetHidGuid;
static GetPreparsedDataFn realGetPreparsedData;
static FreePreparsedDataFn realFreePreparsedData;
static GetCapsFn realGetCaps;
static GetSpecificCapsFn realGetSpecificButtonCaps, realGetSpecificValueCaps;

static HANDLE logFile = INVALID_HANDLE_VALUE;
static CRITICAL_SECTION logLock;

static void loadReal(void) {
    if (real) return;
    WCHAR path[MAX_PATH];
    UINT n = GetSystemDirectoryW(path, MAX_PATH - 10);
    /* A 32-bit process's System32 is redirected to the 32-bit SysWOW64 copy. */
    lstrcpyW(path + n, L"\\hid.dll");
    real = LoadLibraryW(path);
    if (!real) return;
    realSetFeature = (SetGetFeatureFn)GetProcAddress(real, "HidD_SetFeature");
    realGetFeature = (SetGetFeatureFn)GetProcAddress(real, "HidD_GetFeature");
    realGetAttributes = (GetAttributesFn)GetProcAddress(real, "HidD_GetAttributes");
    realGetHidGuid = (GetHidGuidFn)GetProcAddress(real, "HidD_GetHidGuid");
    realGetPreparsedData = (GetPreparsedDataFn)GetProcAddress(real, "HidD_GetPreparsedData");
    realFreePreparsedData = (FreePreparsedDataFn)GetProcAddress(real, "HidD_FreePreparsedData");
    realGetCaps = (GetCapsFn)GetProcAddress(real, "HidP_GetCaps");
    realGetSpecificButtonCaps = (GetSpecificCapsFn)GetProcAddress(real, "HidP_GetSpecificButtonCaps");
    realGetSpecificValueCaps = (GetSpecificCapsFn)GetProcAddress(real, "HidP_GetSpecificValueCaps");
}

static void openLog(void) {
    WCHAR path[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"USERPROFILE", path, MAX_PATH - 40);
    if (n == 0 || n >= MAX_PATH - 40) return;
    lstrcpyW(path + n, L"\\Desktop\\aula-hid-log.txt");
    logFile = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
}

static char *putHex(char *p, unsigned v, int digits) {
    static const char hex[] = "0123456789abcdef";
    for (int i = digits - 1; i >= 0; i--) *p++ = hex[(v >> (i * 4)) & 0xF];
    return p;
}

static char *putDec(char *p, unsigned v, int digits) {
    char tmp[10];
    for (int i = digits - 1; i >= 0; i--) { tmp[i] = (char)('0' + v % 10); v /= 10; }
    for (int i = 0; i < digits; i++) *p++ = tmp[i];
    return p;
}

static char *putStr(char *p, const char *s) {
    while (*s) *p++ = *s++;
    return p;
}

/* One line: "HH:MM:SS.mmm <tag> h=<handle> len=<n> ok=<0|1> <hex bytes>" */
static void logLine(const char *tag, HANDLE h, const BYTE *data, ULONG len, BOOLEAN ok) {
    if (logFile == INVALID_HANDLE_VALUE) return;
    static char line[8192];
    EnterCriticalSection(&logLock);
    SYSTEMTIME t;
    GetLocalTime(&t);
    char *p = line;
    p = putDec(p, t.wHour, 2); *p++ = ':';
    p = putDec(p, t.wMinute, 2); *p++ = ':';
    p = putDec(p, t.wSecond, 2); *p++ = '.';
    p = putDec(p, t.wMilliseconds, 3); *p++ = ' ';
    p = putStr(p, tag);
    p = putStr(p, " h="); p = putHex(p, (unsigned)(ULONG_PTR)h, 8);
    p = putStr(p, " len="); p = putDec(p, len, 4);
    p = putStr(p, ok ? " ok=1 " : " ok=0 ");
    ULONG shown = len > 2000 ? 2000 : len;
    for (ULONG i = 0; data && i < shown; i++) { p = putHex(p, data[i], 2); *p++ = ' '; }
    *p++ = '\r'; *p++ = '\n';
    DWORD written;
    WriteFile(logFile, line, (DWORD)(p - line), &written, NULL);
    LeaveCriticalSection(&logLock);
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved) {
    (void)inst; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        InitializeCriticalSection(&logLock);
        openLog();
        static const BYTE none[1] = {0};
        logLine("START hid logger loaded", NULL, none, 0, TRUE);
    } else if (reason == DLL_PROCESS_DETACH && logFile != INVALID_HANDLE_VALUE) {
        CloseHandle(logFile);
    }
    return TRUE;
}

BOOLEAN WINAPI HidD_SetFeature(HANDLE h, PVOID buf, ULONG len) {
    loadReal();
    /* Record the request first, so a report that hangs the device is still logged. */
    logLine("SET", h, (const BYTE *)buf, len, TRUE);
    BOOLEAN ok = realSetFeature ? realSetFeature(h, buf, len) : FALSE;
    if (!ok) logLine("SET-FAILED", h, NULL, len, ok);
    return ok;
}

BOOLEAN WINAPI HidD_GetFeature(HANDLE h, PVOID buf, ULONG len) {
    loadReal();
    BOOLEAN ok = realGetFeature ? realGetFeature(h, buf, len) : FALSE;
    logLine("GET", h, (const BYTE *)buf, len, ok);
    return ok;
}

BOOLEAN WINAPI HidD_GetAttributes(HANDLE h, PVOID attrs) {
    loadReal();
    BOOLEAN ok = realGetAttributes ? realGetAttributes(h, attrs) : FALSE;
    /* HIDD_ATTRIBUTES: ULONG Size; USHORT VendorID; USHORT ProductID; USHORT VersionNumber */
    logLine("ATTR", h, ok ? (const BYTE *)attrs + 4 : NULL, ok ? 6 : 0, ok);
    return ok;
}

void WINAPI HidD_GetHidGuid(LPGUID guid) {
    loadReal();
    if (realGetHidGuid) realGetHidGuid(guid);
}

BOOLEAN WINAPI HidD_GetPreparsedData(HANDLE h, PVOID *data) {
    loadReal();
    return realGetPreparsedData ? realGetPreparsedData(h, data) : FALSE;
}

BOOLEAN WINAPI HidD_FreePreparsedData(PVOID data) {
    loadReal();
    return realFreePreparsedData ? realFreePreparsedData(data) : FALSE;
}

LONG WINAPI HidP_GetCaps(PVOID data, PVOID caps) {
    loadReal();
    return realGetCaps ? realGetCaps(data, caps) : (LONG)0xC0110001;
}

LONG WINAPI HidP_GetSpecificButtonCaps(ULONG type, ULONG page, ULONG link, ULONG usage, PVOID caps, PUSHORT len, PVOID data) {
    loadReal();
    return realGetSpecificButtonCaps ? realGetSpecificButtonCaps(type, page, link, usage, caps, len, data) : (LONG)0xC0110001;
}

LONG WINAPI HidP_GetSpecificValueCaps(ULONG type, ULONG page, ULONG link, ULONG usage, PVOID caps, PUSHORT len, PVOID data) {
    loadReal();
    return realGetSpecificValueCaps ? realGetSpecificValueCaps(type, page, link, usage, caps, len, data) : (LONG)0xC0110001;
}
