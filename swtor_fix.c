#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdbool.h>
#include <windows.h>
#include <winternl.h>
#include <tlhelp32.h>

typedef NTSTATUS (WINAPI *NTQUERYSYSTEMTIME)(PLARGE_INTEGER);
typedef NTSTATUS (WINAPI *NTQUERYSYSTEMINFORMATION)(SYSTEM_INFORMATION_CLASS,
  PVOID, ULONG, PULONG);

// KUSER_SHARED_DATA offsets, defined here to not inclue ddk..
#define ADDR_INTERRUPTTIME_HIGH2TIME  0x7FFE0010
#define ADDR_INTERRUPTTIME_LOWPART    0x7FFE0008
#define ADDR_INTERRUPTTIME_HIGH1TIME  0x7FFE000C
#define ADDR_SYSTEMTIME_HIGH2TIME     0x7FFE001C
#define ADDR_SYSTEMTIME_LOWPART       0x7FFE0014
#define ADDR_SYSTEMTIME_HIGH1TIME     0x7FFE0018
#define ADDR_TICKCOUNT_HIGH2TIME      0x7FFE0328
#define ADDR_TICKCOUNT_LOWPART        0x7FFE0320
#define ADDR_TICKCOUNT_HIGH1TIME      0x7FFE0324
#define ADDR_TICKCOUNTLOWDEPRECATED   0x7FFE0000
#define KUSD_INTERRUPTTIME_HIGH2TIME  (*((DWORD*)ADDR_INTERRUPTTIME_HIGH2TIME))
#define KUSD_INTERRUPTTIME_LOWPART    (*((DWORD*)ADDR_INTERRUPTTIME_LOWPART))
#define KUSD_INTERRUPTTIME_HIGH1TIME  (*((DWORD*)ADDR_INTERRUPTTIME_HIGH1TIME))
#define KUSD_SYSTEMTIME_HIGH2TIME     (*((DWORD*)ADDR_SYSTEMTIME_HIGH2TIME))
#define KUSD_SYSTEMTIME_LOWPART       (*((DWORD*)ADDR_SYSTEMTIME_LOWPART))
#define KUSD_SYSTEMTIME_HIGH1TIME     (*((DWORD*)ADDR_SYSTEMTIME_HIGH1TIME))
#define KUSD_TICKCOUNT_HIGH2TIME      (*((DWORD*)ADDR_TICKCOUNT_HIGH2TIME))
#define KUSD_TICKCOUNT_LOWPART        (*((DWORD*)ADDR_TICKCOUNT_LOWPART))
#define KUSD_TICKCOUNT_HIGH1TIME      (*((DWORD*)ADDR_TICKCOUNT_HIGH1TIME))
#define KUSD_TICKCOUNTLOWDEPRECATED   (*((DWORD*)ADDR_TICKCOUNTLOWDEPRECATED))

static NTQUERYSYSTEMTIME nt_qst = NULL;
static ULONGLONG start_time;
static DWORD pid = 0;
static HANDLE target;
static int done = 0;
static int timer_interval;

void update_shared_data_time(void)
{
  LARGE_INTEGER now, start, irq;
  LONGLONG     d11, d12, d13, d14, remainder;
  nt_qst(&now);

  irq.QuadPart = (now.QuadPart - start_time);

  KUSD_INTERRUPTTIME_HIGH2TIME  = irq.HighPart;
  KUSD_INTERRUPTTIME_LOWPART    = irq.LowPart;
  KUSD_INTERRUPTTIME_HIGH1TIME  = irq.HighPart;

  KUSD_SYSTEMTIME_HIGH2TIME = now.HighPart;
  KUSD_SYSTEMTIME_LOWPART   = now.LowPart;
  KUSD_SYSTEMTIME_HIGH1TIME = now.HighPart;

  /* start.QuadPart = irq.QuadPart / 10000; */
  /* b0.110100011011011100010111010110001110 (8192/10000) */
  d12 = irq.QuadPart + (irq.QuadPart >> 1); /* b1100 = 12 */
  d11 = irq.QuadPart + (d12 >> 2);          /* b1011 = 11 */
  d13 = d12 + (irq.QuadPart >> 3);          /* b1101 = 13 */
  d14 = d12 + (irq.QuadPart >> 2);          /* b1110 = 14 */

  start.QuadPart  = d13 + (d13 >> 7) + (d11 >> 11);
  start.QuadPart += (irq.QuadPart >> 15) + (irq.QuadPart >> 19);
  start.QuadPart += (d14 >> 21) + (d11 >> 25) + (d14 >> 32);     /* intermediate=quotient*8192     */
  start.QuadPart  = start.QuadPart >> 14;                        /* intermediate=intermediate/8192 */
  remainder = irq.QuadPart - start.QuadPart*10000;
  start.QuadPart += ((remainder + 452) >> 12);            /* round to nearest ~5000 = (4096+904/2) */

  KUSD_TICKCOUNT_HIGH2TIME    = start.HighPart;
  KUSD_TICKCOUNT_LOWPART      = start.LowPart;
  KUSD_TICKCOUNT_HIGH1TIME    = start.HighPart;
  KUSD_TICKCOUNTLOWDEPRECATED = start.LowPart;
}

DWORD wait_for_swtor(void)
{
  fprintf(stderr, "Waiting for swtor...\n");
  fflush(stderr);

  DWORD swtor_pid = 0;
  PROCESSENTRY32 p_entry;
  p_entry.dwSize = sizeof(PROCESSENTRY32);
  HANDLE h = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);

  Process32First(h, &p_entry);

  while (1) {
    if (!Process32Next(h, &p_entry))
    {
      CloseHandle(h);
      h = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
      Process32First(h, &p_entry);
    }
    if (strcmp(p_entry.szExeFile, "swtor.exe") == 0)
    {
      swtor_pid = p_entry.th32ProcessID;
      fprintf(stderr, "Found, PID: %ld\n", swtor_pid);
      break;
    }
  }

  CloseHandle(h);

  return swtor_pid;
}

void copy_to_target(void)
{
  DWORD out;
  WriteProcessMemory(target, (LPVOID)ADDR_INTERRUPTTIME_HIGH2TIME,
    (LPCVOID)ADDR_INTERRUPTTIME_HIGH2TIME, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_INTERRUPTTIME_LOWPART,
    (LPCVOID)ADDR_INTERRUPTTIME_LOWPART, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_INTERRUPTTIME_HIGH1TIME,
    (LPCVOID)ADDR_INTERRUPTTIME_HIGH1TIME, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_SYSTEMTIME_HIGH2TIME,
    (LPCVOID)ADDR_SYSTEMTIME_HIGH2TIME, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_SYSTEMTIME_LOWPART,
    (LPCVOID)ADDR_SYSTEMTIME_LOWPART, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_SYSTEMTIME_HIGH1TIME,
    (LPCVOID)ADDR_SYSTEMTIME_HIGH1TIME, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_TICKCOUNT_HIGH2TIME,
    (LPCVOID)ADDR_TICKCOUNT_HIGH2TIME, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_TICKCOUNT_LOWPART,
    (LPCVOID)ADDR_TICKCOUNT_LOWPART, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_TICKCOUNT_HIGH1TIME,
    (LPCVOID)ADDR_TICKCOUNT_HIGH1TIME, sizeof(DWORD), &out);
  WriteProcessMemory(target, (LPVOID)ADDR_TICKCOUNTLOWDEPRECATED,
    (LPCVOID)ADDR_TICKCOUNTLOWDEPRECATED, sizeof(DWORD), &out);
}

DWORD WINAPI shared_data_thread(LPVOID arg)
{
  (void)arg;

  while (!done)
  {
    update_shared_data_time();
    copy_to_target();
    Sleep(timer_interval);
  }

  return 0;
}

DWORD WINAPI is_target_dead_thread(LPVOID arg)
{
  (void)arg;

  DWORD ret;

  while (1) {
    HANDLE swtor = OpenProcess(SYNCHRONIZE, FALSE, pid);
    ret = WaitForSingleObject(swtor, 0);
    CloseHandle(swtor);
    if (ret != WAIT_TIMEOUT)
    {
      done = 1;
      break;
    }
    Sleep(250);
  }

  return 0;
}

bool is_number(char number[])
{
    for (int i=0; number[i] != 0; i++)
    {
        if (!isdigit(number[i]))
            return false;
    }
    return true;
}

int main(int argc, char *argv[])
{
  if ((argc == 1) || !is_number(argv[1]))
  {
    fprintf(stderr, "%s: usage: %s sleep-interval-time(millseconds)\n", argv[0], argv[0]);
    return 1;
  }
  timer_interval=atoi(argv[1]);

  HMODULE ntdll = LoadLibrary("ntdll");

  SYSTEM_TIMEOFDAY_INFORMATION ti;
  NTQUERYSYSTEMINFORMATION nt_qsi =
    (NTQUERYSYSTEMINFORMATION)GetProcAddress(ntdll, "NtQuerySystemInformation");
  nt_qst = (NTQUERYSYSTEMTIME)GetProcAddress(ntdll, "NtQuerySystemTime");
  FreeLibrary(ntdll);

  nt_qsi(SystemTimeOfDayInformation, &ti, sizeof(ti), NULL);
  start_time = ti.BootTime.QuadPart;

  pid = wait_for_swtor();
  target = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_WRITE, FALSE, pid);

  HANDLE threads[2];
  threads[0] = CreateThread(NULL, 0, shared_data_thread, NULL, 0, NULL);
  threads[1] = CreateThread(NULL, 0, is_target_dead_thread, NULL, 0, NULL);

  fprintf(stderr, "%s: Waiting for threads to end...\n", argv[0]);
  fflush(stderr);

  WaitForMultipleObjects(2, threads, TRUE, INFINITE);

  CloseHandle(threads[0]);
  CloseHandle(threads[1]);
  CloseHandle(target);

  return 0;
}

