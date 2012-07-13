unit Iocp.TimerQueue;

{����Win32ϵͳ��ʱ�Ӷ���
��Ҫ���ڼ��IOCP�����Ƿ�ʱ
}

interface

uses
  Windows, Classes, SysUtils, SyncObjs, System.Generics.Collections, Iocp.Logger;

type
  TIocpTimerQueueTimer = class;
  TIocpTimerQueueTimerList = TList<TIocpTimerQueueTimer>;
  TIocpTimerQueue = class
  private
    FRefCount: Integer;
    FTimerQueueHandle: THandle;
    FTimerList: TIocpTimerQueueTimerList;
    FLocker: TCriticalSection;
  protected
  public
    constructor Create; virtual;
    destructor Destroy; override;

    function AddRef: Integer;
    function Release: Boolean;

    property Handle: THandle read FTimerQueueHandle;
    property RefCount: Integer read FRefCount;
  end;

  TIocpTimerQueueTimer = class
  private
    FTimerQueue: TIocpTimerQueue;
    FTimerHandle: THandle;
    FInterval: DWORD;
    FRefCount: Integer;
    FOnTimer: TNotifyEvent;
    FOnCancel: TNotifyEvent;

    procedure SetInterval(const Value: DWORD);
  protected
    procedure Execute; virtual;
    procedure Cancel; virtual;
  public
    constructor Create(TimerQueue: TIocpTimerQueue; Interval: DWORD); virtual;
    destructor Destroy; override;

    function AddRef: Integer;
    function Release: Boolean;

    property Interval: DWORD read FInterval write SetInterval;
    property OnTimer: TNotifyEvent read FOnTimer write FOnTimer;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
  end;

implementation

procedure WaitOrTimerCallback(Timer: TIocpTimerQueueTimer; TimerOrWaitFired: ByteBool); stdcall;
begin
  try
    Timer.Execute;
  except
  end;
end;

{ TIocpTimerQueue }

constructor TIocpTimerQueue.Create;
begin
  FTimerQueueHandle := CreateTimerQueue();
  FTimerList := TIocpTimerQueueTimerList.Create;
  FLocker := TCriticalSection.Create;
  FRefCount := 1;
end;

destructor TIocpTimerQueue.Destroy;
var
  Timer: TIocpTimerQueueTimer;
begin
  DeleteTimerQueueEx(FTimerQueueHandle, 0);

  try
    FLocker.Enter;
    for Timer in FTimerList do
      Timer.Cancel;
  finally
    FLocker.Leave;
  end;

  FTimerList.Free;
  FLocker.Free;

  inherited Destroy;
end;

function TIocpTimerQueue.AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TIocpTimerQueue.Release: Boolean;
begin
  Result := (InterlockedDecrement(FRefCount) = 0);
  if not Result then Exit;

  Free;
end;

{ TIocpTimerQueueTimer }

constructor TIocpTimerQueueTimer.Create(TimerQueue: TIocpTimerQueue; Interval: DWORD);
begin
  FTimerQueue := TimerQueue;
  FInterval := Interval;
  FRefCount := 1;

  // ����DueTime����Ϊ100����ʾ100����������Timer
  // ��������Ϊ����Timer�ȴ����󴴽���ɣ�������ܻ����Timer�з��ʶ��󣬵��Ƕ�����δ�����ɹ�
  if not CreateTimerQueueTimer(FTimerHandle, FTimerQueue.Handle, @WaitOrTimerCallback, Pointer(Self), 100, FInterval, 0) then
  begin
    raise Exception.Create('CreateTimerQueueTimer failed');
  end;

  try
    FTimerQueue.AddRef;
    FTimerQueue.FLocker.Enter;
    FTimerQueue.FTimerList.Add(Self);
  finally
    FTimerQueue.FLocker.Leave;
  end;
end;

destructor TIocpTimerQueueTimer.Destroy;
begin
  DeleteTimerQueueTimer(FTimerQueue.Handle, FTimerHandle, 0);

  try
    FTimerQueue.FLocker.Enter;
    FTimerQueue.FTimerList.Remove(Self);
  finally
    FTimerQueue.FLocker.Leave;
    FTimerQueue.Release;
  end;

  inherited Destroy;
end;

function TIocpTimerQueueTimer.AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TIocpTimerQueueTimer.Release: Boolean;
begin
  Result := (InterlockedDecrement(FRefCount) = 0);
  if not Result then Exit;

  Free;
end;

procedure TIocpTimerQueueTimer.Execute;
begin
  if Assigned(FOnTimer) then
    FOnTimer(Self);
end;

procedure TIocpTimerQueueTimer.Cancel;
begin
  if Assigned(FOnCancel) then
    FOnCancel(Self);
end;

procedure TIocpTimerQueueTimer.SetInterval(const Value: DWORD);
begin
  FInterval := Value;
  ChangeTimerQueueTimer(FTimerQueue.Handle, FTimerHandle, 0, FInterval)
end;

end.
