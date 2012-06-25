unit IocpThreadPool;

{*
  ����IOCPʵ�ֵ��̳߳أ�Ч��Զ������ͨ�̳߳�
  ����Synopse�е��̳߳ش���ı�
 *}

interface

uses
  Windows, Classes, SysUtils, Math, IocpApiFix;

const
  SHUTDOWN_FLAG = ULONG_PTR(-1);

type
  TThreadsPool = class;
  TProcessorThread = class;

  // �����������ݵĻ�����
  TThreadRequest = class(TObject)
  protected
    // �̳߳ع�������
    // �̳����������д�Լ����̴߳���
    procedure Execute(Thread: TProcessorThread); virtual;
  end;

  // �����߳�
  TProcessorThread = class(TThread)
  private
    FPool: TThreadsPool;
    FTag: Pointer;
  protected
    procedure Execute; override;
  public
    constructor Create(Pool: TThreadsPool); reintroduce; virtual;

    property Tag: Pointer read FTag write FTag;
  end;

  TProcessorThreadArray = array of TProcessorThread;

  // �̳߳�
  TThreadsPool = class
  protected
    FIocpHandle: THandle;
    FNumberOfThreads: Integer;
    FThreads: TProcessorThreadArray;
    FThreadHandles: array of THandle;
    FPendingRequest: Integer;

    // �߳������¼�
    procedure DoThreadStart(Thread: TProcessorThread); virtual;

    // �߳̽����¼�
    procedure DoThreadExit(Thread: TProcessorThread); virtual;
  public
    // NumberOfThreads=�߳��������<=0���Զ�����CPU��������������߳���
    constructor Create(NumberOfThreads: Integer = 0; Suspend: Boolean = False);
    destructor Destroy; override;

    function AddRequest(Request: TThreadRequest): Boolean; virtual;
    procedure Startup;
    procedure Shutdown;

    property Threads: TProcessorThreadArray read FThreads;
    property PendingRequest: Integer read FPendingRequest;
  end;

implementation

{ TThreadRequest }

procedure TThreadRequest.Execute(Thread: TProcessorThread);
begin
end;

{ TProcessorThread }

constructor TProcessorThread.Create(Pool: TThreadsPool);
begin
  inherited Create(True);

  FreeOnTerminate := True;
  FPool := Pool;

  FTag := nil;
  Suspended := False;
end;

procedure TProcessorThread.Execute;
var
  Bytes: DWORD;
  Request: TThreadRequest;
  CompKey: ULONG_PTR;
begin
  FPool.DoThreadStart(Self);
  while not Terminated and IocpApiFix.GetQueuedCompletionStatus(FPool.FIocpHandle, Bytes, CompKey, POverlapped(Request), INFINITE) do
  try
    // ������Ч�����󣬺���
    if (CompKey <> ULONG_PTR(FPool)) then Continue;

    // �յ��߳��˳���־������ѭ��
    if (ULONG_PTR(Request) = SHUTDOWN_FLAG) then Break;

    if (Request <> nil) then
    try
      Request.Execute(Self);
    finally
      InterlockedDecrement(FPool.FPendingRequest);
      Request.Free;
    end;
  except
  end;
  FPool.DoThreadExit(Self);
end;

{ TThreadsPool }

// NumberOfThreads �߳���������趨Ϊ0�����Զ�����CPU��������������߳���
constructor TThreadsPool.Create(NumberOfThreads: Integer; Suspend: Boolean);
begin
  FNumberOfThreads := NumberOfThreads;
  FIocpHandle := 0;

  if not Suspend then
    Startup;
end;

destructor TThreadsPool.Destroy;
begin
  Shutdown;
  inherited Destroy;
end;

procedure TThreadsPool.DoThreadStart(Thread: TProcessorThread);
begin
end;

procedure TThreadsPool.DoThreadExit(Thread: TProcessorThread);
begin
end;

function TThreadsPool.AddRequest(Request: TThreadRequest): Boolean;
begin
  Result := False;
  if (FIocpHandle = 0) then Exit;

  InterlockedIncrement(FPendingRequest);
  Result := IocpApiFix.PostQueuedCompletionStatus(FIocpHandle, 0, ULONG_PTR(Self), POverlapped(Request));
  if not Result then
    InterlockedDecrement(FPendingRequest);
end;

procedure TThreadsPool.Startup;
var
  NumberOfThreads, i: Integer;
  si: TSystemInfo;
begin
  if (FIocpHandle <> 0) then Exit;

  if (FNumberOfThreads <= 0) then
  begin
    GetSystemInfo(si);
    NumberOfThreads := si.dwNumberOfProcessors * 2 + 2;
  end else
    NumberOfThreads := Min(FNumberOfThreads, 64); // maximum count for WaitForMultipleObjects()

  // ������ɶ˿�
  // NumberOfConcurrentThreads = 0 ��ʾÿ��CPU����һ�������߳�
  // ��ʵ�ʲ��Է��֣������߳������ֻ����ÿ��CPUһ������IOCP�󲢷�����Ĵ����л���ִ�������������ѻ�
  // �Ӷ������ڴ�Ĵ������ģ�������������Ϊ������������NumberOfThreads�ܱ�֤�߼����󾡿��ܿ�ı���Ӧ
  // �����ڴ����ļ����������ʲô��Ĳ������շ��ٶȻ���΢���ͣ����������������ȫֵ�õģ�
  FIocpHandle := IocpApiFix.CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, NumberOfThreads);
  if (FIocpHandle = INVALID_HANDLE_VALUE) then
    raise Exception.Create('IocpThreadPool����IOCP����ʧ��');

  // �������й����߳�
  Setlength(FThreads, NumberOfThreads);
  SetLength(FThreadHandles, NumberOfThreads);
  for i := 0 to NumberOfThreads - 1 do
  begin
    FThreads[i] := TProcessorThread.Create(Self);
    FThreadHandles[i] := FThreads[i].Handle;
  end;
end;

procedure TThreadsPool.Shutdown;
var
  i: Integer;
begin
  if (FIocpHandle = 0) then Exit;

  // �����й����̷߳����˳�����
  for i := 0 to High(FThreads) do
    IocpApiFix.PostQueuedCompletionStatus(FIocpHandle, 0, ULONG_PTR(Self), POverLapped(SHUTDOWN_FLAG));

  // �ȴ������߳̽���
  WaitForMultipleObjects(Length(FThreadHandles), Pointer(FThreadHandles), True, INFINITE);

  // �ر���ɶ˿ھ��
  CloseHandle(FIocpHandle);
  FIocpHandle := 0;

  SetLength(FThreads, 0);
  SetLength(FThreadHandles, 0);
end;

end.
