void stub_midivol(int vol);
void stub_wavevol(int vol);
void unloadRealDLL();
MCIERROR WINAPI relay_mciSendCommandA(MCIDEVICEID a0, UINT a1, DWORD a2, DWORD a3);
MCIERROR WINAPI relay_mciSendStringA(LPCSTR a0, LPSTR a1, UINT a2, HWND a3);
MCIERROR WINAPI relay_mciSendCommandW(MCIDEVICEID a0, UINT a1, DWORD a2, DWORD a3);
MCIERROR WINAPI relay_mciSendStringW(LPCWSTR a0, LPWSTR a1, UINT a2, HWND a3);
