unit IocpTcpSocket;

{���ڿͻ���Socket�أ�
�ͻ���ʹ��ConnectEx������Socket���ӣ�ֻ���ڷ���������Ͽ�����������Socket���ܱ����ã�
������ɿͻ��˷����DisconnectEx�Ͽ������Socket���ܱ����ã����Կͻ���Ҫ�����Ͽ����ӵĻ�
��ֱ����shutdown��closesocket�Ϳ����ˡ�

��ConnectEx��ʱ���ȴ�Socket���в����Ѿ��ɷ������Ͽ��Ŀ���Socket������о����ã�û�о��½�

--����ǿͻ��˵�Socket���û���

������һ�����Է��֣��ͻ��˵�Socket�����൱���ȶ������Ի���ֱ�ӹر�Socket�ȽϿɿ�

ZY. 2012.01.13

ֱ�ӷ���Socket���ã���Ϊ�����һЩ���ȶ����أ������ܵ������ֲ��Ǻܴ�

ZY. 2012.04.19
}

// �������������أ�������TCP/IP��Nagle�㷨
// Ҳ���ǲ��ܷ��͵����ݿ��Ƿ��������ײ�Ļ��壬��ֱ�ӷ���ȥ
// ���һ���̶Ƚ��ͷ���Ч�ʣ������������Ӧ�ٶ�
//{$define __TCP_NODELAY__}

// ** ��������0����������Ҫ�򿪣�����ʵ�ʲ��Է��ִ򿪺󷴶��ٶȻ������½�
// ** �����ײ�Ļ�����ƻ��Ǻܸ�Ч��

// ���ͻ���0��������������ʱֱ��ʹ�ó����趨�Ļ��棬���ÿ�����Socket�ײ㻺��
//{$define __TCP_SNDBUF_ZERO_COPY__}

// ���ջ���0��������������ʱֱ��ʹ�ó����趨�Ļ��棬���ô�Socket�ײ㻺�濽��
//{$define __TCP_RCVBUF_ZERO_COPY__}

// ���ó�ʱ���ʱ��
{$DEFINE __TIME_OUT_TIMER__}

interface

uses
  Windows, Messages, Classes, SysUtils, SyncObjs, Math, Contnrs, System.Generics.Collections,
  IdWinsock2, IdWship6, IocpApiFix, IocpThreadPool, IocpReadWriteLocker, IocpMemoryPool,
  IocpObjectPool, IocpBuffer, IocpQueue, IocpTimerQueue, IocpLogger, IocpUtils, DSiWin32;

const
  SHUTDOWN_FLAG = ULONG_PTR(-1);

  MAX_FREE_HANDLE_DATA_BLOCKS = 512;
  MAX_FREE_IO_DATA_BLOCKS = MAX_FREE_HANDLE_DATA_BLOCKS * 2;
  INIT_ACCEPTEX_NUM = 1;
  NET_CACHE_SIZE = 4 * 1024; // ��Ҫ����4K !!!!!
  FILE_CACHE_SIZE = 64 * 1024;

type
  EIocpTcpException = class(Exception);

  TSimpleIocpTcpServer = class;
  TIocpTcpSocket = class;
  TIocpSocketConnection = class;

  TIocpOperationType = (iotReadZero, iotRead, iotWrite, iotAccept, iotConnect);

  {
    *** ���Ͷ������ݿ�ṹ ***
    ���ڱ��汻��ֺ���ڴ��
  }
  {PIocpIoBlock = ^TIocpIoBlock;
  TIocpIoBlock = record
    Buf: Pointer;
    Size: Integer;
  end;}

  {
    *** ���Ͷ��� ***
    ���������ڴ������ڴ滺��ؿ��С��ֺ�,���浽������
  }
(*  TIocpSendQueue = class
  private
    FLocker: TCriticalSection;
    FIocpQueue: TIocpPointerQueue;
    FOwner: TIocpSocketConnection;

    function GetCount: Integer;
    function UnsafePushBuffer(Buf: Pointer; Size: Integer): Boolean;
    function UnsafePopBuffer(out Buf: Pointer; out Size: Integer): Boolean;
  protected
    function Push(p: Pointer): Boolean; virtual;
    function Pop(out p: Pointer): Boolean; virtual;
  public
    constructor Create(Owner: TIocpSocketConnection); virtual;
    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;

    function PushBuffer(Buf: Pointer; Size: Integer): Boolean;
    function PopBuffer(out Buf: Pointer; out Size: Integer): Boolean;
    procedure Clear;

    property Count: Integer read GetCount;
  end; *)

  {
     *** Socket ���� ***
  }
  TIocpSocketConnection = class(TIocpObject)
  private
    FSocket: TSocket;
    FRemoteAddr: TSockAddr;
    FRemoteIP: string;
    FRemotePort: Word;

    FRefCount: Integer;
    FDisconnected: Integer;
    FFirstTick, FLastTick: DWORD;
    FTag: Pointer;
    FSndBufSize, FRcvBufSize: Integer;
    FRcvBuffer: Pointer;
    FPendingSend: Integer;
    FPendingRecv: Integer;
    {$IFDEF __TIME_OUT_TIMER__}
    FTimer: TIocpTimerQueueTimer;
    FTimeout: DWORD;
    FLife: DWORD;
    // ���ӳ�ʱ���
    procedure OnTimerExecute(Sender: TObject);
    procedure OnTimerCancel(Sender: TObject);
    {$ENDIF}

    function GetRefCount: Integer;
    function GetIsClosed: Boolean;
    function GetOwner: TIocpTcpSocket;

    function InitSocket: Boolean;
    procedure UpdateTick;

    procedure IncPendingRecv;
    procedure DecPendingRecv;
    function PostReadZero: Boolean;
    function PostRead: Boolean;

    procedure IncPendingSend;
    procedure DecPendingSend;
    function PostWrite(const Buf: Pointer; Size: Integer): Boolean;

    function _TriggerClientRecvData(Buf: Pointer; Len: Integer): Boolean;
    function _TriggerClientSentData(Buf: Pointer; Len: Integer): Boolean;
    function _Send(Buf: Pointer; Size: Integer): Integer;
  protected
    procedure Initialize; override;
    procedure Finalize; override;

    {$IFDEF __TIME_OUT_TIMER__}
    procedure TriggerTimeout; virtual;
    procedure TriggerLifeout; virtual;
    {$ENDIF}

    function GetIsIdle: Boolean; virtual;
  public
    constructor Create(AOwner: TObject); override;
    destructor Destroy; override;

    function AddRef: Integer;
    function Release: Boolean;
    procedure Disconnect;

    // ���첽����
    function Send(Buf: Pointer; Size: Integer): Integer; overload; virtual;
    function Send(const Bytes: TBytes): Integer; overload;
    function Send(const s: RawByteString): Integer; overload;
    function Send(const s: string): Integer; overload;
    function Send(Stream: TStream): Integer; overload;

    property Owner: TIocpTcpSocket read GetOwner;
    property Socket: TSocket read FSocket;
    property RefCount: Integer read GetRefCount;
    property FirstTick: DWORD read FFirstTick;
    property LastTick: DWORD read FLastTick;

    property PeerIP: string read FRemoteIP;
    property PeerAddr: string read FRemoteIP;
    property PeerPort: Word read FRemotePort;
    property IsClosed: Boolean read GetIsClosed;
    property IsIdle: Boolean read GetIsIdle;
    property SndBufSize: Integer read FSndBufSize;
    property RcvBufSize: Integer read FRcvBufSize;
    property PendingSend: Integer read FPendingSend;
    property PendingRecv: Integer read FPendingRecv;
    {$IFDEF __TIME_OUT_TIMER__}
    property Timeout: DWORD read FTimeout write FTimeout;
    property Life: DWORD read FLife write FLife;
    {$ENDIF}
    property Tag: Pointer read FTag write FTag;
  end;

  TIocpSocketConnectionClass = class of TIocpSocketConnection;

  TPerIoBufUnion = record
    case Integer of
      0: (DataBuf: WSABUF);
      // ���Bufferֻ����AcceptEx�����ն˵�ַ���ݣ���СΪ2����ַ�ṹ
      1: (AcceptExBuffer: array[0..(SizeOf(TSockAddrIn) + 16) * 2 - 1] of Byte);
  end;

  {
    *** ��IO���ݽṹ
    ÿ��IO��������Ҫ����һ���ýṹ���ݸ�IOCP
  }
  PIocpPerIoData = ^TIocpPerIoData;
  TIocpPerIoData = record
    Overlapped: TWSAOverlapped;
    Buffer: TPerIoBufUnion;
    Operation: TIocpOperationType;
    ListenSocket, ClientSocket: TSocket;

    BytesTransfered: Cardinal;
  end;

  {
    *** Socket�����б� ***
  }
  TIocpSocketConnectionPair = TPair<TSocket, TIocpSocketConnection>;
  TIocpSocketConnectionDictionary = class(TDictionary<TSocket, TIocpSocketConnection>)
  private
    FOwner: TIocpTcpSocket;

    function GetItem(Socket: TSocket): TIocpSocketConnection;
    procedure SetItem(Socket: TSocket; const Value: TIocpSocketConnection);
  public
    constructor Create(AOwner: TIocpTcpSocket); virtual;

    procedure Assign(const Source: TIocpSocketConnectionDictionary);
    function Delete(Socket: TSocket): Boolean;

    property Item[Socket: TSocket]: TIocpSocketConnection read GetItem write SetItem; default;
  end;

  {
    *** IO�����߳� ***
    ������Ҫ�������շ��߳�,��IOCP�̳߳ص���
  }
  TIocpIoThread = class(TThread)
  private
    FOwner: TIocpTcpSocket;
  protected
    procedure Execute; override;
  public
    constructor Create(IocpSocket: TIocpTcpSocket); reintroduce;
  end;

  {
    *** Accept�߳� ***
    ������AcceptEx�׽��ֲ���ʱ�����µ��׽���
  }
  TIocpAcceptThread = class(TThread)
  private
    FOwner: TIocpTcpSocket;
    FListenSocket: TSocket;
    FInitAcceptNum: Integer;
    FShutdownEvent: THandle;
  protected
    procedure Execute; override;
  public
    constructor Create(IocpSocket: TIocpTcpSocket; ListenSocket: TSocket; InitAcceptNum: Integer); reintroduce;

    procedure Quit;
    property ListenSocket: TSocket read FListenSocket;
  end;

  TIocpNotifyEvent = function(Sender: TObject; Client: TIocpSocketConnection): Boolean of object;
  TIocpDataEvent = function(Sender: TObject; Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean of object;

  {
    *** ��Ҫ��Socketʵ���� ***
  }
  TIocpTcpSocket = class(TComponent)
  private
    FIocpHandle: THandle;
    FIoThreadsNumber: Integer;
    FIoThreads: array of TIocpIoThread;
    FIoThreadHandles: array of THandle;
    FPendingRequest: Integer;
    FConnectionPool: TIocpObjectPool;
    FPerIoDataPool: TIocpMemoryPool;
    FConnectionList, FIdleConnectionList: TIocpSocketConnectionDictionary;
    FConnectionListLocker: TCriticalSection;
    FListenThreads: TList;
    FListenThreadsLocker: TCriticalSection;
    {$IFDEF __TIME_OUT_TIMER__}
    FTimerQueue: TIocpTimerQueue;
    FTimeout: DWORD;
    FClientLife: DWORD;
    {$ENDIF}
    FMaxClients: Integer;
    FSentBytes, FRecvBytes: Int64;
    FOnClientConnected: TIocpNotifyEvent;
    FOnClientSentData: TIocpDataEvent;
    FOnClientRecvData: TIocpDataEvent;
    FOnClientDisconnected: TIocpNotifyEvent;

    procedure ProcessRequest(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData; IoThread: TIocpIoThread); virtual;
    procedure ExtractAddrInfo(const Addr: TSockAddr; out IP: string; out Port: Word);
    function GetConnectionFreeMemory: Integer;
    function GetConnectionUsedMemory: Integer;
    function GetPerIoFreeMemory: Integer;
    function GetPerIoUsedMemory: Integer;
    function GetConnectionClass: TIocpSocketConnectionClass;
    procedure SetConnectionClass(const Value: TIocpSocketConnectionClass);
    function GetIoCacheFreeMemory: Integer;
    function GetIoCacheUsedMemory: Integer;

    function AllocConnection(Socket: TSocket): TIocpSocketConnection;
    procedure FreeConnection(Connection: TIocpSocketConnection);
    function AllocIoData(Socket: TSocket; Operation: TIocpOperationType): PIocpPerIoData;
    procedure FreeIoData(PerIoData: PIocpPerIoData);

    function AssociateSocketWithCompletionPort(Socket: TSocket; Connection: TIocpSocketConnection): Boolean;
    function PostNewAcceptEx(ListenSocket: TSocket): Boolean;

    procedure RequestAcceptComplete(PerIoData: PIocpPerIoData);
    procedure RequestConnectComplete(Connection: TIocpSocketConnection);
    procedure RequestReadZeroComplete(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);
    procedure RequestReadComplete(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);
    procedure RequestWriteComplete(Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);

    function _TriggerClientConnected(Client: TIocpSocketConnection): Boolean;
    function _TriggerClientDisconnected(Client: TIocpSocketConnection): Boolean;
    function _TriggerClientRecvData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean;
    function _TriggerClientSentData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean;
  protected
    function ProcessMessage: Boolean;
    procedure MessagePump;

    procedure StartupWorkers; virtual;
    procedure ShutdownWorkers; virtual;

    // �������漸����������ʵ����IO�¼�����ʱ����Ӧ����
    // ���ӽ���ʱ����
    function TriggerClientConnected(Client: TIocpSocketConnection): Boolean; virtual;

    // ���ӶϿ�ʱ����
    function TriggerClientDisconnected(Client: TIocpSocketConnection): Boolean; virtual;

    // ���յ�����ʱ����
    function TriggerClientRecvData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean; virtual;

    // �����������ʱ����
    // ����Bufֻ��ָ�뱾���ǿ��԰�ȫʹ�õģ�����ָ����ڴ����ݺ��п����Ѿ����ͷ���
    // ����ǧ��Ҫ������¼���ȥ���Է���Buf��ָ�������
    function TriggerClientSentData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean; virtual;
  public
    constructor Create(AOwner: TComponent); overload; override;
    constructor Create(AOwner: TComponent; IoThreadsNumber: Integer); reintroduce; overload;
    destructor Destroy; override;

    function Listen(const Host: string; Port: Word; InitAcceptNum: Integer): TSocket; overload;
    function Listen(Port: Word; InitAcceptNum: Integer): TSocket; overload;
    procedure StopListen(ListenSocket: TSocket);
    procedure CloseSocket(Socket: TSocket);
    function AsyncConnect(const RemoteAddr: string; RemotePort: Word; Tag: Pointer = nil): TSocket;
    function Connect(const RemoteAddr: string; RemotePort: Word; Tag: Pointer = nil; ConnectTimeout: DWORD = 10000): TIocpSocketConnection;
    procedure DisconnectAll;

    function LockConnectionList: TIocpSocketConnectionDictionary;
    procedure UnlockConnectionList;

    property ConnectionClass: TIocpSocketConnectionClass read GetConnectionClass write SetConnectionClass;
    property ConnectionList: TIocpSocketConnectionDictionary read FConnectionList;
    property ConnectionUsedMemory: Integer read GetConnectionUsedMemory;
    property ConnectionFreeMemory: Integer read GetConnectionFreeMemory;
    property PerIoDataPool: TIocpMemoryPool read FPerIoDataPool;
    property PerIoUsedMemory: Integer read GetPerIoUsedMemory;
    property PerIoFreeMemory: Integer read GetPerIoFreeMemory;
    property IoCacheUsedMemory: Integer read GetIoCacheUsedMemory;
    property IoCacheFreeMemory: Integer read GetIoCacheFreeMemory;
    property SentBytes: Int64 read FSentBytes;
    property RecvBytes: Int64 read FRecvBytes;
    property PendingRequest: Integer read FPendingRequest;
    {$IFDEF __TIME_OUT_TIMER__}
    property TimerQueue: TIocpTimerQueue read FTimerQueue;
    {$ENDIF}
  published
    {$IFDEF __TIME_OUT_TIMER__}
    property Timeout: DWORD read FTimeout write FTimeout default 0;
    property ClientLife: DWORD read FClientLife write FClientLife default 0;
    {$ENDIF}
    property MaxClients: Integer read FMaxClients write FMaxClients default 0;
    property OnClientConnected: TIocpNotifyEvent read FOnClientConnected write FOnClientConnected;
    property OnClientDisconnected: TIocpNotifyEvent read FOnClientDisconnected write FOnClientDisconnected;
    property OnClientRecvData: TIocpDataEvent read FOnClientRecvData write FOnClientRecvData;
    property OnClientSentData: TIocpDataEvent read FOnClientSentData write FOnClientSentData;
  end;

  TIocpLineSocketConnection = class(TIocpSocketConnection)
  private
    FLineText: TIocpStringStream;
  public
    constructor Create(AOwner: TObject); override;
    destructor Destroy; override;

    function Send(const s: RawByteString): Integer; reintroduce;

    property LineText: TIocpStringStream read FLineText;
  end;

  TIocpLineRecvEvent = procedure(Sender: TObject; Client: TIocpLineSocketConnection; Line: RawByteString) of object;
  TIocpLineSocket = class(TIocpTcpSocket)
  private
    FLineLimit: Integer;
    FLineEndTag: RawByteString;
    FOnRecvLine: TIocpLineRecvEvent;

    procedure SetLineEndTag(const Value: RawByteString);
  protected
    function TriggerClientRecvData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean; override;

    procedure ParseRecvData(Client: TIocpLineSocketConnection; Buf: Pointer; Len: Integer); virtual;

    // ������������������洦����յ����ı���
    procedure DoOnRecvLine(Client: TIocpLineSocketConnection; Line: RawByteString); virtual;
  public
    constructor Create(AOwner: TComponent); override;

    function Connect(const RemoteAddr: string; RemotePort: Word; Tag: Pointer = nil; ConnectTimeout: DWORD = 10000): TIocpLineSocketConnection;
  published
    property LineEndTag: RawByteString read FLineEndTag write SetLineEndTag;
    property LineLimit: Integer read FLineLimit write FLineLimit default 65536;
    property OnRecvLine: TIocpLineRecvEvent read FOnRecvLine write FOnRecvLine;
  end;

  TIocpLineServer = class(TIocpLineSocket)
  private
    FAddr: string;
    FPort: Word;
    FListenSocket: TSocket;
  public
    constructor Create(AOwner: TComponent); override;

    function Start: Boolean;
    function Stop: Boolean;
  published
    property Addr: string read FAddr write FAddr;
    property Port: Word read FPort write FPort;
  end;

  TSimpleIocpTcpClient = class(TIocpTcpSocket)
  private
    FServerPort: Word;
    FServerAddr: string;
  public
    function AsyncConnect(Tag: Pointer = nil): TSocket;
    function Connect(Tag: Pointer = nil; ConnectTimeout: DWORD = 10000): TIocpSocketConnection;
  published
    property ServerAddr: string read FServerAddr write FServerAddr;
    property ServerPort: Word read FServerPort write FServerPort;
  end;

  TSimpleIocpTcpServer = class(TIocpTcpSocket)
  private
    FAddr: string;
    FPort: Word;
    FListenSocket: TSocket;
    FInitAcceptNum: Integer;
    FStartTick: DWORD;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function Start: Boolean;
    function Stop: Boolean;

    property StartTick: DWORD read FStartTick;
  published
    property Addr: string read FAddr write FAddr;
    property Port: Word read FPort write FPort;
    property InitAcceptNum: Integer read FInitAcceptNum write FInitAcceptNum default INIT_ACCEPTEX_NUM;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Iocp', [TIocpTcpSocket, TSimpleIocpTcpClient, TSimpleIocpTcpServer, TIocpLineSocket, TIocpLineServer]);
end;

var
  IoCachePool, {IoQueuePool, }FileCachePool: TIocpMemoryPool;

{ TIocpSendQueue }
(*
procedure TIocpSendQueue.Clear;
var
  Buf: Pointer;
  Size: Integer;
begin
  try
    Lock;
    while UnsafePopBuffer(Buf, Size) do
      IoCachePool.FreeMemory(Buf);
  finally
    Unlock;
  end;
end;

constructor TIocpSendQueue.Create(Owner: TIocpSocketConnection);
begin
  FLocker := TCriticalSection.Create;
  FIocpQueue := TIocpPointerQueue.Create;
  FOwner := Owner;
end;

destructor TIocpSendQueue.Destroy;
begin
  Clear;
  FIocpQueue.Free;
  FLocker.Free;

  inherited Destroy;
end;

function TIocpSendQueue.GetCount: Integer;
begin
  Result := FIocpQueue.Count;
end;

procedure TIocpSendQueue.Lock;
begin
  FLocker.Enter;
end;

function TIocpSendQueue.Pop(out p: Pointer): Boolean;
begin
  Result := FIocpQueue.Pop(p);
end;

function TIocpSendQueue.PopBuffer(out Buf: Pointer; out Size: Integer): Boolean;
begin
  try
    Lock;
    Result := UnsafePopBuffer(Buf, Size);
  finally
    Unlock;
  end;
end;

function TIocpSendQueue.Push(p: Pointer): Boolean;
begin
  Result := FIocpQueue.Push(p);
end;

function TIocpSendQueue.PushBuffer(Buf: Pointer; Size: Integer): Boolean;
begin
  try
    Lock;
    Result := UnsafePushBuffer(Buf, Size);
  finally
    Unlock;
  end;
end;

procedure TIocpSendQueue.Unlock;
begin
  FLocker.Leave;
end;

function TIocpSendQueue.UnsafePushBuffer(Buf: Pointer; Size: Integer): Boolean;
var
  BlockSize: Integer;
  PBlock: PIocpIoBlock;
begin
  if (Buf = nil) or (Size <= 0) then Exit(False);

  while (Size > 0) do
  begin
    BlockSize := Min(Size, IoCachePool.BlockSize);
    PBlock := IoQueuePool.GetMemory;
    PBlock.Buf := IoCachePool.GetMemory;
    Move(Buf^, PBlock.Buf^, BlockSize);
    PBlock.Size := BlockSize;
    if not Push(PBlock) then Exit(False);

    Dec(Size, BlockSize);
    Inc(PByte(Buf), BlockSize);
  end;
  Result := True;
end;

function TIocpSendQueue.UnsafePopBuffer(out Buf: Pointer;
  out Size: Integer): Boolean;
var
  PBlock: PIocpIoBlock;
begin
  if Pop(Pointer(PBlock)) then
  begin
    Buf := PBlock.Buf;
    Size := PBlock.Size;
    IoQueuePool.FreeMemory(Pointer(PBlock));
    Result := (Buf <> nil);
  end
  else
  begin
    Buf := nil;
    Size := -1;
    Result := False;
  end;
end; *)

{ TIocpSocketConnection }

constructor TIocpSocketConnection.Create(AOwner: TObject);
begin
  inherited Create(AOwner);

  FRcvBuffer := IoCachePool.GetMemory;
end;

destructor TIocpSocketConnection.Destroy;
begin
  IoCachePool.FreeMemory(FRcvBuffer);

  inherited Destroy;
end;

function TIocpSocketConnection.AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TIocpSocketConnection.Release: Boolean;
begin
  Result := (InterlockedDecrement(FRefCount) = 0);
  if not Result then Exit;

  // ���Socket��û�رգ�����Ҫ�رգ��������ɾ��й¶
  // �������������Զ�������Ͽ�����
  if (InterlockedExchange(FDisconnected, 1) = 0) then
    Owner.CloseSocket(FSocket);

  Owner._TriggerClientDisconnected(Self);
  Owner.FreeConnection(Self);
end;

procedure TIocpSocketConnection.Disconnect;
begin
  if (InterlockedExchange(FDisconnected, 1) <> 0) then Exit;

  Owner.CloseSocket(FSocket);
  Release;
end;

procedure TIocpSocketConnection.DecPendingRecv;
begin
  InterlockedDecrement(FPendingRecv);
end;

procedure TIocpSocketConnection.DecPendingSend;
begin
  InterlockedDecrement(FPendingSend);
end;

procedure TIocpSocketConnection.Finalize;
begin
end;

function TIocpSocketConnection.GetIsClosed: Boolean;
begin
  Result := (InterlockedExchange(FDisconnected, FDisconnected) = 1);
end;

function TIocpSocketConnection.GetIsIdle: Boolean;
begin
  Result := not GetIsClosed and (FPendingSend = 0) and (FPendingRecv = 0)
end;

function TIocpSocketConnection.GetOwner: TIocpTcpSocket;
begin
  Result := TIocpTcpSocket(inherited Owner);
end;

function TIocpSocketConnection.GetRefCount: Integer;
begin
  Result := InterlockedExchange(FRefCount, FRefCount);
end;

function TIocpSocketConnection.InitSocket: Boolean;
var
{$IF defined(__TCP_SNDBUF_ZERO_COPY__) or defined(__TCP_RCVBUF_ZERO_COPY__)}
  BufSize: Integer;
{$IFEND}
{$IF not (defined(__TCP_SNDBUF_ZERO_COPY__) and defined(__TCP_RCVBUF_ZERO_COPY__))}
  OptLen: Integer;
{$IFEND}
{$IFDEF __TCP_NODELAY__}
  NagleValue: Byte;
{$ENDIF}
begin
  Result := False;

{$IFDEF __TCP_SNDBUF_ZERO_COPY__}
  BufSize := 0;
  if (setsockopt(FSocket, SOL_SOCKET, SO_SNDBUF,
    PAnsiChar(@BufSize), SizeOf(BufSize)) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.setsockopt.SO_SNDBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
  FSndBufSize := IoCachePool.BlockSize;
{$ELSE}
  OptLen := SizeOf(FSndBufSize);
  if (getsockopt(FSocket, SOL_SOCKET, SO_SNDBUF,
    PAnsiChar(@FSndBufSize), OptLen) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.getsockopt.SO_SNDBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
{$ENDIF}

{$IFDEF __TCP_RCVBUF_ZERO_COPY__}
  BufSize := 0;
  if (setsockopt(FSocket, SOL_SOCKET, SO_RCVBUF,
    PAnsiChar(@BufSize), SizeOf(BufSize)) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.setsockopt.SO_RCVBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
  FRcvBufSize := IoCachePool.BlockSize;
{$ELSE}
  OptLen := SizeOf(FRcvBufSize);
  if (getsockopt(FSocket, SOL_SOCKET, SO_RCVBUF,
    PAnsiChar(@FRcvBufSize), OptLen) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.getsockopt.SO_RCVBUF ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
{$ENDIF}

{$IFDEF __TCP_NODELAY__}
  NagleValue := 1;
  if (setsockopt(FSocket, IPPROTO_TCP, TCP_NODELAY, PAnsiChar(@NagleValue), SizeOf(Byte)) = SOCKET_ERROR) then
  begin
    AppendLog('%s.InitSocket.setsockopt.TCP_NODELAY ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
    Exit;
  end;
{$ENDIF}

  Result := True;
end;

procedure TIocpSocketConnection.IncPendingRecv;
begin
  InterlockedIncrement(FPendingRecv);
end;

procedure TIocpSocketConnection.IncPendingSend;
begin
  InterlockedIncrement(FPendingSend);
end;

procedure TIocpSocketConnection.Initialize;
begin
  FSocket := 0;
  FRefCount := 1; // �ó�ʼ���ü��� 1
  FPendingSend := 0;
  FPendingRecv := 0;
  FDisconnected := 0;
  FLastTick := 0;
  FTag := nil;

  ZeroMemory(@FRemoteAddr, SizeOf(TSockAddrIn));
  FRemoteIP := '';
  FRemotePort := 0;

  FFirstTick := GetTickCount;

  {$IFDEF __TIME_OUT_TIMER__}
  FTimeout := Owner.Timeout;
  FLife := Owner.ClientLife;
  AddRef; // ΪTimer�����������ü���
  FTimer := TIocpTimerQueueTimer.Create(Owner.FTimerQueue, 1000);
  FTimer.OnTimer := OnTimerExecute;
  FTimer.OnCancel := OnTimerCancel;
  {$ENDIF}
end;

function TIocpSocketConnection._Send(Buf: Pointer; Size: Integer): Integer;
var
  BlockSize: Integer;
begin
  if IsClosed then Exit(-1);

  Result := Size;

  // ��IocpHttpServer��ʵ�ʲ����з��֣���Server���͵Ŀ����4K��ʱ��
  // ������յ��������п��ܻ���ֻ��ң�����������������ｫ���͵���
  // ����ֳ�4K��С�鷢��
  while (Size > 0) do
  begin
    BlockSize := Min(IoCachePool.BlockSize, Size);
    if not PostWrite(Buf, BlockSize) then Exit(-2);
    Inc(PAnsiChar(Buf), BlockSize);
    Dec(Size, BlockSize);
  end;
end;

function TIocpSocketConnection.Send(Buf: Pointer; Size: Integer): Integer;
begin
  Result := _Send(Buf, Size);
end;

function TIocpSocketConnection.Send(const Bytes: TBytes): Integer;
begin
  Result := Send(Pointer(Bytes), Length(Bytes));
end;

function TIocpSocketConnection.Send(const s: RawByteString): Integer;
begin
  Result := Send(Pointer(s), Length(s));
end;

function TIocpSocketConnection.Send(const s: string): Integer;
begin
  Result := Send(Pointer(s), Length(s) * SizeOf(Char));
end;

function TIocpSocketConnection.Send(Stream: TStream): Integer;
var
  Buf: Pointer;
  BufSize, BlockSize: Integer;
begin
  BufSize := FileCachePool.BlockSize;
  Buf := FileCachePool.GetMemory;
  try
    Stream.Position := 0;
    while True do
    begin
      BlockSize := Stream.Read(Buf^, BufSize);
      if (BlockSize = 0) then Break;

      if (_Send(Buf, BlockSize) < 0) then Exit(-1);
    end;

    Result := Stream.Size;
  finally
    FileCachePool.FreeMemory(Buf);
  end;
end;

function TIocpSocketConnection._TriggerClientRecvData(Buf: Pointer; Len: Integer): Boolean;
begin
  Result := True;
end;

function TIocpSocketConnection._TriggerClientSentData(Buf: Pointer;
  Len: Integer): Boolean;
begin
  IoCachePool.FreeMemory(Buf);
  Result := True;
end;

{$IFDEF __TIME_OUT_TIMER__}
procedure TIocpSocketConnection.OnTimerExecute(Sender: TObject);
begin
  try
    if IsClosed then
    begin
      FTimer.Release; // ���ӶϿ�ʱ����TimerҲ�ͷŵ�������Timer�ٴδ��������쳣����
      Release; // ��ӦTimer����ʱ��AddRef(procedure Initialize)
      Exit;
    end;

    // ��ʱ,�Ͽ�����
    if (FTimeout > 0) and (FLastTick > 0) and (CalcTickDiff(FLastTick, GetTickCount) > FTimeout) then
    begin
      TriggerTimeout;
      FTimer.Release; // ���ӶϿ�ʱ����TimerҲ�ͷŵ�������Timer�ٴδ��������쳣����
      Release; // ��ӦTimer����ʱ��AddRef(procedure Initialize)
      Disconnect;
      Exit;
    end;

    // ����������,�Ͽ�����
    if (FLife > 0) and (FFirstTick > 0) and (CalcTickDiff(FFirstTick, GetTickCount) > FLife) then
    begin
      TriggerLifeout;
      FTimer.Release; // ���ӶϿ�ʱ����TimerҲ�ͷŵ�������Timer�ٴδ��������쳣����
      Release; // ��ӦTimer����ʱ��AddRef(procedure Initialize)
      Disconnect;
      Exit;
    end;
  except
  end;
end;

procedure TIocpSocketConnection.OnTimerCancel(Sender: TObject);
begin
  Release; // ��ӦTimer����ʱ��AddRef(procedure Initialize)
  FTimer.Release; // ���ӶϿ�ʱ����TimerҲ�ͷŵ�������Timer�ٴδ��������쳣����
end;

procedure TIocpSocketConnection.TriggerTimeout;
begin
end;

procedure TIocpSocketConnection.TriggerLifeout;
begin
end;
{$ENDIF}

function TIocpSocketConnection.PostReadZero: Boolean;
var
  PerIoData: PIocpPerIoData;
  Bytes, Flags: Cardinal;
  LastErr: Integer;
begin
  Result := False;
  if IsClosed then Exit;

  // �������ü���
  // �������1��˵���������ڹر�����
  if (AddRef = 1) then Exit;

  PerIoData := Owner.AllocIoData(FSocket, iotReadZero);
  PerIoData.Buffer.DataBuf.Buf := nil;
  PerIoData.Buffer.DataBuf.Len := 0;
  Flags := 0;
  Bytes := 0;
  if (WSARecv(PerIoData.ClientSocket, @PerIoData.Buffer.DataBuf, 1, Bytes, Flags, PWSAOverlapped(PerIoData), nil) = SOCKET_ERROR)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    LastErr := WSAGetLastError;
    if (LastErr <> WSAECONNABORTED) and (LastErr <> WSAECONNRESET) then
      AppendLog('%s.Socket%d PostReadZero.WSARecv ERROR %d=%s', [ClassName, FSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Release; // ��Ӧ������ͷ�� AddRef
    Disconnect; // ��Ӧ���ӳ�ʼ��ʱ�� FRefCount := 1
    Owner.FreeIoData(PerIoData);
    Exit;
  end;

  Result := True;
end;

function TIocpSocketConnection.PostRead: Boolean;
var
  PerIoData: PIocpPerIoData;
  Bytes, Flags: Cardinal;
  LastErr: Integer;
begin
  Result := False;
  if IsClosed then Exit;

  // �������ü���
  // �������1��˵���������ڹر�����
  if (AddRef = 1) then Exit;

  IncPendingRecv;

  PerIoData := Owner.AllocIoData(FSocket, iotRead);
  PerIoData.Buffer.DataBuf.Buf := FRcvBuffer;
  PerIoData.Buffer.DataBuf.Len := IoCachePool.BlockSize;

  Flags := 0;
  Bytes := 0;
  if (WSARecv(PerIoData.ClientSocket, @PerIoData.Buffer.DataBuf, 1, Bytes, Flags, PWSAOverlapped(PerIoData), nil) = SOCKET_ERROR)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    LastErr := WSAGetLastError;
    if (LastErr <> WSAECONNABORTED) and (LastErr <> WSAECONNRESET) then
      AppendLog('%s.Socket%d PostRead.WSARecv ERROR %d=%s', [ClassName, FSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
    DecPendingRecv;
    Release; // ��Ӧ������ͷ�� AddRef
    Disconnect; // ��Ӧ���ӳ�ʼ��ʱ�� FRefCount := 1
    Owner.FreeIoData(PerIoData);
    Exit;
  end;

  Result := True;
end;

function TIocpSocketConnection.PostWrite(const Buf: Pointer; Size: Integer): Boolean;
var
  PerIoData: PIocpPerIoData;
  Bytes: DWORD;
  LastErr: Integer;
  SndBuf: Pointer;
begin
  if IsClosed then Exit(False);

  // �������ü���
  // �������1��˵���������ڹر�����
  if (AddRef = 1) then Exit(False);

  IncPendingSend;

  SndBuf := IoCachePool.GetMemory;
  CopyMemory(SndBuf, Buf, Size);

  PerIoData := Owner.AllocIoData(FSocket, iotWrite);
  PerIoData.Buffer.DataBuf.Buf := SndBuf;
  PerIoData.Buffer.DataBuf.Len := Size;

  // WSAEFAULT(10014)
  // The lpBuffers, lpNumberOfBytesSent, lpOverlapped, lpCompletionRoutine parameter
  // is not totally contained in a valid part of the user address space.
  if (WSASend(FSocket, @PerIoData.Buffer.DataBuf, 1, Bytes, 0, PWSAOverlapped(PerIoData), nil) = SOCKET_ERROR)
    and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    LastErr := WSAGetLastError;
    if (LastErr <> WSAECONNABORTED) and (LastErr <> WSAECONNRESET) then
      AppendLog('%s.Socket%d PostWrite.WSASend error, ERR=%d,%s', [ClassName, FSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
    DecPendingSend;
    Release; // ��Ӧ������ͷ�� AddRef
    Disconnect; // ��Ӧ���ӳ�ʼ��ʱ�� FRefCount := 1
    Owner.FreeIoData(PerIoData);
    IoCachePool.FreeMemory(SndBuf);
    Exit(False);
  end;

  Result := True;
end;

procedure TIocpSocketConnection.UpdateTick;
begin
  FLastTick := GetTickCount;
end;

{ TIocpSocketConnectionDictionary }

constructor TIocpSocketConnectionDictionary.Create(AOwner: TIocpTcpSocket);
begin
  inherited Create;

  FOwner := AOwner;
end;

procedure TIocpSocketConnectionDictionary.Assign(const Source: TIocpSocketConnectionDictionary);
var
  Pair: TIocpSocketConnectionPair;
begin
  FOwner := Source.FOwner;
  Clear;
  for Pair in Source do
    AddOrSetValue(Pair.Key, Pair.Value);
end;

function TIocpSocketConnectionDictionary.GetItem(Socket: TSocket): TIocpSocketConnection;
begin
  if not TryGetValue(Socket, Result) then
    Result := nil;
end;

procedure TIocpSocketConnectionDictionary.SetItem(Socket: TSocket;
  const Value: TIocpSocketConnection);
begin
  AddOrSetValue(Socket, Value);
end;

function TIocpSocketConnectionDictionary.Delete(Socket: TSocket): Boolean;
begin
  Result := ContainsKey(Socket);
  if Result then
    Remove(Socket);
end;

{ TIocpIoThread }

constructor TIocpIoThread.Create(IocpSocket: TIocpTcpSocket);
begin
  inherited Create(True);

  FreeOnTerminate := True;
  FOwner := IocpSocket;

  Suspended := False;
end;

procedure TIocpIoThread.Execute;
const
  ERROR_ABANDONED_WAIT_0 = 735;
var
  IocpStatusOk: Boolean;
  BytesTransferred: Cardinal;
  Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData;
  LastErr: DWORD;
begin
//  AppendLog('%s.IoThread %d start', [FOwner.ClassName, ThreadID]);
  while not Terminated do
  try
    IocpStatusOk := IocpApiFix.GetQueuedCompletionStatus(FOwner.FIocpHandle,
      BytesTransferred, ULONG_PTR(Connection), POverlapped(PerIoData), WSA_INFINITE);

    {
    (1) ���I/O����(WSASend() / WSARecv())�ɹ����,��ô����ֵΪTRUE,���� lpNumberOfBytes Ϊ�Ѵ��͵��ֽ���.ע��,�Ѵ��͵��ֽ����п���С����������/���յ��ֽ���.
    (2) ����Է��ر����׽���,��ô���������
    (a) I/O�����Ѿ������һ����,����WSASend()������1K�ֽ�,�������е�512�ֽ��Ѿ��������,�򷵻�ֵΪTRUE, lpNumberOfBytes ָ���ֵΪ512, lpOverlapped ��Ч.
    (b) I/O����û�����,��ô����ֵΪFALSE, lpNumberOfBytes ָ���ֵΪ0, lpCompletionKey, lpOverlapped ��Ч.
    (3) ������ǳ����ⷽ�����ر����׽���,���(2)�����һ��,û������.
    (4) �����������������,�򷵻�ֵΪFALSE,���� lpCompletionKey, lpOverlapped = NULL,�����������,Ӧ�õ��� GetLastError() �鿴������Ϣ,�����˳��ȴ�GetQueuedCompletionStatus()��ѭ��.
    }

    if not IocpStatusOk then
    begin
      if (PerIoData = nil) and (Connection = nil) then
      begin
        LastErr := GetLastError;
        if (LastErr <> ERROR_ABANDONED_WAIT_0) then
          AppendLog('%s Io�߳� %d ����. ERR %d=%s', [FOwner.ClassName, ThreadID, LastErr, SysErrorMessage(LastErr)], ltError);
        Break;
      end;

      if (PerIoData <> nil) then
        FOwner.FreeIoData(PerIoData);

      if (Connection <> nil) then
      begin
        Connection.Release; // ��ӦPostRead/PostWrite�е�AddRef
        Connection.Disconnect; // ��Ӧ���Ӵ���ʱ��FRefCount := 1
      end;

      Continue;
    end;

    if (BytesTransferred = 0) and (ULONG_PTR(PerIoData) = SHUTDOWN_FLAG) then Break;
    if (Connection = nil) and (PerIoData = nil) then Continue;

    PerIoData.BytesTransfered := BytesTransferred;
    FOwner.ProcessRequest(Connection, PerIoData, Self);
  except
    on e: Exception do
      AppendLog('TIocpIoThread.Execute, %s=%s', [e.ClassName, e.Message], ltException);
  end;

//  AppendLog('%s.IoThread %d exit', [FOwner.ClassName, ThreadID]);
end;

{ TIocpAcceptThread }

constructor TIocpAcceptThread.Create(IocpSocket: TIocpTcpSocket;
  ListenSocket: TSocket; InitAcceptNum: Integer);
begin
  inherited Create(True);

  FreeOnTerminate := True;

  FOwner := IocpSocket;
  FInitAcceptNum := InitAcceptNum;
  FListenSocket := ListenSocket;
  FShutdownEvent := CreateEvent(nil, True, False, nil);

  Suspended := False;
end;

procedure TIocpAcceptThread.Execute;
var
  i: Integer;
  LastErr: Integer;
  AcceptEvents: array[0..1] of THandle;
  RetEvents: TWSANetworkEvents;
  dwRet: DWORD;
begin
//  AppendLog('%s.AcceptThread %d start', [FOwner.ClassName, ThreadID]);
  try
    for i := 1 to FInitAcceptNum do
      FOwner.PostNewAcceptEx(FListenSocket);

    AcceptEvents[0] := WSACreateEvent; // �½�һ���¼����ڰ� FD_ACCEPT
    AcceptEvents[1] := FShutdownEvent;
    try
      // �󶨼����˿ڵ�ACCEPT�¼�����û���㹻��Accept�׽���ʱ�ͻᴥ�����¼�
      WSAEventSelect(FListenSocket, AcceptEvents[0], FD_ACCEPT);

      while not Terminated do
      begin
        // �ȴ��˳�����ACCEPT�¼�
        dwRet := WSAWaitForMultipleEvents(2, @AcceptEvents[0], False, INFINITE, True);

        // �յ��˳��¼�֪ͨ
        if (dwRet = WSA_WAIT_EVENT_0 + 1) or (dwRet = WSA_WAIT_FAILED) or Terminated then Break;

        // ��ȡ�¼�״̬
        if (WSAEnumNetworkEvents(FListenSocket, AcceptEvents[0], @RetEvents) = SOCKET_ERROR) then
        begin
          LastErr := WSAGetLastError;
          AppendLog('%s.WSAEnumNetworkEventsʧ��, ERROR %d=%s', [ClassName, LastErr, SysErrorMessage(LastErr)], ltWarning);
          Break;
        end;

        // ���ACCEPT�¼���������Ͷ���µ�Accept�׽���
        // ÿ��Ͷ��32��
        if (RetEvents.lNetworkEvents and FD_ACCEPT = FD_ACCEPT) then
        begin
          if (RetEvents.iErrorCode[FD_ACCEPT_BIT] <> 0) then
          begin
            LastErr := WSAGetLastError;
            AppendLog('%s.WSAEnumNetworkEventsʧ��, ERROR %d=%s', [ClassName, LastErr, SysErrorMessage(LastErr)], ltWarning);
            Break;
          end;

          for i := 1 to 32 do
          begin
            if not FOwner.PostNewAcceptEx(FListenSocket) then Break;
          end;
        end;
      end;
      FOwner.CloseSocket(FListenSocket);
    finally
      CloseHandle(AcceptEvents[0]);
      CloseHandle(AcceptEvents[1]);
    end;
  except
    on e: Exception do
      AppendLog('%s.Execute, %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
//  AppendLog('%s.AcceptThread %d exit', [FOwner.ClassName, ThreadID]);
end;

procedure TIocpAcceptThread.Quit;
begin
  SetEvent(FShutdownEvent);
end;

{ TIocpTcpSocket }

constructor TIocpTcpSocket.Create(AOwner: TComponent; IoThreadsNumber: Integer);
begin
  inherited Create(AOwner);

  FConnectionPool := TIocpObjectPool.Create(Self, TIocpSocketConnection, MAX_FREE_HANDLE_DATA_BLOCKS);
  FPerIoDataPool := TIocpMemoryPool.Create(SizeOf(TIocpPerIoData), MAX_FREE_IO_DATA_BLOCKS);
  FConnectionList := TIocpSocketConnectionDictionary.Create(Self);
  FConnectionListLocker := TCriticalSection.Create;
  FIdleConnectionList := TIocpSocketConnectionDictionary.Create(Self);

  FListenThreads := TList.Create;
  FListenThreadsLocker := TCriticalSection.Create;

  FIoThreadsNumber := IoThreadsNumber;
  FIocpHandle := 0;
  {$IFDEF __TIME_OUT_TIMER__}
  FTimeout := 0;
  FClientLife := 0;
  {$ENDIF}
  FMaxClients := 0;
  StartupWorkers;
end;

constructor TIocpTcpSocket.Create(AOwner: TComponent);
begin
  Create(AOwner, 0);
end;

destructor TIocpTcpSocket.Destroy;
begin
  ShutdownWorkers;

  FConnectionList.Free;
  FConnectionListLocker.Free;
  FIdleConnectionList.Free;
  FListenThreads.Free;
  FListenThreadsLocker.Free;
  FConnectionPool.Free;
  FPerIoDataPool.Free;

  inherited Destroy;
end;

function TIocpTcpSocket.PostNewAcceptEx(ListenSocket: TSocket): Boolean;
var
  PerIoData: PIocpPerIoData;
  ClientSocket: TSocket;
  Bytes: Cardinal;
  LastErr: Integer;
  Connection: TIocpSocketConnection;
begin
  Result := False;

  ClientSocket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
  if (ClientSocket = INVALID_SOCKET) then
  begin
    LastErr := WSAGetLastError;
    AppendLog('%s.PostNewAcceptEx.ΪAcceptEx����Socketʧ��, ERR=%d,%s', [ClassName, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Exit;
  end;

  // �����µ����Ӷ���
  Connection := AllocConnection(ClientSocket);

  // �����ӷŵ����������б���
  // ��ShutdownWorks�в��������ͷ�Socket��Դ����������Socket���й¶
  try
    FConnectionListLocker.Enter;
    FIdleConnectionList[ClientSocket] := Connection;
  finally
    FConnectionListLocker.Leave;
  end;

  PerIoData := AllocIoData(ClientSocket, iotAccept);
  PerIoData.ListenSocket := ListenSocket;
  if (not AcceptEx(ListenSocket, ClientSocket, @PerIoData.Buffer.AcceptExBuffer[0], 0,
    SizeOf(TSockAddrIn) + 16, SizeOf(TSockAddrIn) + 16, Bytes, POverlapped(PerIoData))) then
  begin
    LastErr := WSAGetLastError;
    if (LastErr <> WSA_IO_PENDING) then
    begin
      AppendLog('%s.PostNewAcceptEx.����AcceptExʧ��(ListenSocket=%d, ClientSocket=%d), ERR=%d,%s', [ClassName, ListenSocket, ClientSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
      FreeIoData(PerIoData);
      Connection.Disconnect;
      Exit;
    end;
  end;

  Result := True;
end;

function TIocpTcpSocket.AllocConnection(Socket: TSocket): TIocpSocketConnection;
begin
  Result := TIocpSocketConnection(FConnectionPool.GetObject);

  Result.FSocket := Socket;
end;

function TIocpTcpSocket.AssociateSocketWithCompletionPort(Socket: TSocket;
  Connection: TIocpSocketConnection): Boolean;
begin
  Result := (IocpApiFix.CreateIoCompletionPort(Socket, FIocpHandle, ULONG_PTR(Connection), 0) <> 0);
  if not Result then
    AppendLog(Format('��IOCPʧ��,Socket=%d, ERR=%d,%s', [Socket, GetLastError, SysErrorMessage(GetLastError)]), ltError);
end;

function TIocpTcpSocket.AllocIoData(Socket: TSocket;
  Operation: TIocpOperationType): PIocpPerIoData;
begin
  Result := FPerIoDataPool.GetMemory;
  Result.ClientSocket := Socket;
  Result.Operation := Operation;

  ZeroMemory(@Result.Overlapped, SizeOf(TWSAOverlapped));
end;

procedure TIocpTcpSocket.DisconnectAll;
var
  Client: TIocpSocketConnection;
begin
  try
    FConnectionListLocker.Enter;

    // X.Values.ToArray�������б���һ������Ϊ���ӶϿ����
    // �Զ��Ӷ�Ӧ�Ĺ���/�����б���ɾ���������ɵ��������쳣����
    for Client in FConnectionList.Values.ToArray do
      Client.Disconnect;

    for Client in FIdleConnectionList.Values.ToArray do
      Client.Disconnect;
  finally
    FConnectionListLocker.Leave;
  end;
end;

function TIocpTcpSocket.AsyncConnect(const RemoteAddr: string; RemotePort: Word; Tag: Pointer): TSocket;
var
  InAddrInfo: TAddrInfoW;
  POutAddrInfo: PAddrInfoW;
  Addr, tmpAddr: TSockAddr;
  ClientSocket: TSocket;
  Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData;
  LastErr: Integer;
begin
  Result := INVALID_SOCKET;

  // �����������������
  if (FMaxClients > 0) and (FConnectionList.Count >= FMaxClients) then Exit;

  {
    64λ������gethostbyname���ص����ݽṹ��h_addr_listָ����Ч(ò�Ƹ�4�ֽں͵�4�ֽ�˳��ߵ���)
    ��getaddrinfo���ص����ݲ���������,���ҿ��Լ��IPv4��IPv6,ֻ��Ҫ�򵥵��޸ľ����ó���ͬʱ֧��
    IPv4��IPv6��
  }
  FillChar(InAddrInfo, SizeOf(TAddrInfoW), 0);
  POutAddrInfo := nil;
  if (getaddrinfo(PWideChar(RemoteAddr), nil, @InAddrInfo, @POutAddrInfo) <> 0) then
  begin
    LastErr := WSAGetLastError;
    AppendLog('%s.AsyncConnect getaddrinfoʧ��, ERR=%d,%s', [ClassName, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Exit;
  end;

  ZeroMemory(@Addr, SizeOf(TSockAddr));
  Addr.sin_family := AF_INET;
  Addr.sin_addr.S_addr := POutAddrInfo.ai_addr.sin_addr.S_addr;
  Addr.sin_port := htons(RemotePort);

  freeaddrinfo(POutAddrInfo);

  ClientSocket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
  if (ClientSocket = INVALID_SOCKET) then Exit;

  ZeroMemory(@tmpAddr, SizeOf(tmpAddr));
  tmpAddr.sin_family := AF_INET;
  tmpAddr.sin_addr.S_addr := INADDR_ANY;
  tmpAddr.sin_port := 0;
  if (bind(ClientSocket, @tmpAddr, SizeOf(tmpAddr)) = SOCKET_ERROR) then
  begin
    LastErr := WSAGetLastError;
    IdWinsock2.CloseSocket(ClientSocket);
    AppendLog('%s.AsyncConnect��ConnectEx(%d)�˿�ʧ��, ERR=%d,%s', [ClassName, ClientSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Exit;
  end;

  // �����µ����Ӷ��󲢰󶨵�IOCP
  Connection := AllocConnection(ClientSocket);
  if not AssociateSocketWithCompletionPort(ClientSocket, Connection) then
  begin
    IdWinsock2.CloseSocket(ClientSocket);
    FConnectionPool.FreeObject(Connection);
    Exit;
  end;

  if (Connection.AddRef = 1) then Exit;

  Connection.Tag := Tag;
  Connection.FRemoteAddr := Addr;
  ExtractAddrInfo(Connection.FRemoteAddr, Connection.FRemoteIP, Connection.FRemotePort);
  PerIoData := AllocIoData(ClientSocket, iotConnect);
  if not ConnectEx(ClientSocket, @Addr, SizeOf(TSockAddr), nil, 0, PCardinal(0)^, PWSAOverlapped(PerIoData)) and
    (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    LastErr := WSAGetLastError;
    AppendLog('%s.AsyncConnect.ConnectEx(%d)ʧ��, ERR=%d,%s', [ClassName, ClientSocket, LastErr, SysErrorMessage(LastErr)], ltWarning);
    FreeIoData(PerIoData);
    Connection.Release;
    Connection.Disconnect;
    Exit;
  end;

  Result := ClientSocket;
end;

function TIocpTcpSocket.Connect(const RemoteAddr: string;
  RemotePort: Word; Tag: Pointer; ConnectTimeout: DWORD): TIocpSocketConnection;
var
  Socket: TSocket;
  DummyHandle: THandle;
  t: DWORD;
begin
  Result := nil;
  Socket := AsyncConnect(RemoteAddr, RemotePort, Tag);
  if (Socket = INVALID_SOCKET) then Exit;

  if (ConnectTimeout <= 0) or (ConnectTimeout > 10000) then
    ConnectTimeout := 10000;

  t := GetTickCount;
  DummyHandle := INVALID_HANDLE_VALUE;
  while True do
  begin
    FConnectionListLocker.Enter;
    try
      Result := FConnectionList[Socket];
      if (Result <> nil) then Exit;
    finally
      FConnectionListLocker.Leave;
    end;

    if (MsgWaitForMultipleObjects(0, DummyHandle, False, 100, QS_ALLINPUT) = WAIT_OBJECT_0) then
      MessagePump;
    if (CalcTickDiff(t, GetTickCount) >= ConnectTimeout) then Exit;
  end;
end;

procedure TIocpTcpSocket.ExtractAddrInfo(const Addr: TSockAddr;
  out IP: string; out Port: Word);
begin
  IP := string(inet_ntoa(Addr.sin_addr));
  Port := ntohs(Addr.sin_port);
end;

procedure TIocpTcpSocket.FreeConnection(Connection: TIocpSocketConnection);
begin
  try
    FConnectionListLocker.Enter;
    if not FConnectionList.Delete(Connection.FSocket) then
      FIdleConnectionList.Delete(Connection.FSocket);
    FConnectionPool.FreeObject(Connection);
  finally
    FConnectionListLocker.Leave;
  end;
end;

procedure TIocpTcpSocket.FreeIoData(PerIoData: PIocpPerIoData);
begin
  FPerIoDataPool.FreeMemory(Pointer(PerIoData));
end;

function TIocpTcpSocket.GetConnectionClass: TIocpSocketConnectionClass;
begin
  Result := TIocpSocketConnectionClass(FConnectionPool.ObjectClass);
end;

function TIocpTcpSocket.GetConnectionFreeMemory: Integer;
begin
  Result := FConnectionPool.FreeObjectsSize;
end;

function TIocpTcpSocket.GetConnectionUsedMemory: Integer;
begin
  Result := FConnectionPool.UsedObjectsSize;
end;

function TIocpTcpSocket.GetIoCacheFreeMemory: Integer;
begin
  Result := IoCachePool.FreeBlocksSize + FileCachePool.FreeBlocksSize;
end;

function TIocpTcpSocket.GetIoCacheUsedMemory: Integer;
begin
  Result := IoCachePool.UsedBlocksSize + FileCachePool.UsedBlocksSize;
end;

function TIocpTcpSocket.GetPerIoFreeMemory: Integer;
begin
  Result := FPerIoDataPool.FreeBlocksSize;
end;

function TIocpTcpSocket.GetPerIoUsedMemory: Integer;
begin
  Result := FPerIoDataPool.UsedBlocksSize;
end;

function TIocpTcpSocket.Listen(const Host: string; Port: Word; InitAcceptNum: Integer): TSocket;
var
  ListenSocket: TSocket;
  InAddrInfo: TAddrInfoW;
  POutAddrInfo: PAddrInfoW;
  ListenAddr: u_long;
  ServerAddr: TSockAddrIn;
  LastErr: Integer;
begin
  Result := INVALID_SOCKET;

  // ���������һ����Ч��ַ������õ�ַ
  // ����������б��ص�ַ
  ListenAddr := htonl(INADDR_ANY);
  if (Host <> '') then
  begin
    FillChar(InAddrInfo, SizeOf(TAddrInfoW), 0);
    if (getaddrinfo(PWideChar(Host), nil, @InAddrInfo, @POutAddrInfo) = 0) then
    begin
      ListenAddr := POutAddrInfo.ai_addr.sin_addr.S_addr;
      freeaddrinfo(POutAddrInfo);
    end;
  end;

  ListenSocket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
  if (ListenSocket = INVALID_SOCKET) then Exit;

  ServerAddr.sin_family := AF_INET;
  ServerAddr.sin_addr.S_addr := ListenAddr;
  ServerAddr.sin_port := htons(Port);
  if (bind(ListenSocket, PSockaddr(@ServerAddr), SizeOf(ServerAddr)) = SOCKET_ERROR) then
  begin
    LastErr := WSAGetLastError;
    IdWinsock2.CloseSocket(ListenSocket);
    AppendLog('%s.�󶨼����˿�(%d)ʧ��, ERR=%d,%s', [ClassName, Port, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Exit;
  end;

  if (IdWinsock2.listen(ListenSocket, SOMAXCONN) = SOCKET_ERROR) then
  begin
    LastErr := WSAGetLastError;
    IdWinsock2.CloseSocket(ListenSocket);
    AppendLog('%s.���������˿�(%d)ʧ��, ERR=%d,%s', [ClassName, Port, LastErr, SysErrorMessage(LastErr)], ltWarning);
    Exit;
  end;

  try
    if not AssociateSocketWithCompletionPort(ListenSocket, nil) then
    begin
      IdWinsock2.CloseSocket(ListenSocket);
      AppendLog('%s.�󶨼����˿�(%d)��IOCPʧ��', [ClassName, Port], ltWarning);
      Exit;
    end;

    try
      FListenThreadsLocker.Enter;
      FListenThreads.Add(TIocpAcceptThread.Create(Self, ListenSocket, InitAcceptNum));
    finally
      FListenThreadsLocker.Leave;
    end;

    Result := ListenSocket;
  except
    on e: Exception do
      AppendLog('%s.Listen ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

function TIocpTcpSocket.Listen(Port: Word; InitAcceptNum: Integer): TSocket;
begin
  Result := Listen('', Port, InitAcceptNum);
end;

function TIocpTcpSocket.LockConnectionList: TIocpSocketConnectionDictionary;
begin
  Result := FConnectionList;
  FConnectionListLocker.Enter;
end;

procedure TIocpTcpSocket.UnlockConnectionList;
begin
  FConnectionListLocker.Leave;
end;

procedure TIocpTcpSocket.MessagePump;
begin
  while ProcessMessage do;
end;

function TIocpTcpSocket.ProcessMessage: Boolean;
var
  Msg: TMsg;
begin
  Result := False;
  if PeekMessage(Msg, 0, 0, 0, PM_REMOVE) then
  begin
    Result := True;
    if (Msg.Message = WM_QUIT) then
    begin
    end
    else
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
  end;
end;

procedure TIocpTcpSocket.ProcessRequest(Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData; IoThread: TIocpIoThread);
begin
  try
    try
      case PerIoData.Operation of
        iotAccept:   RequestAcceptComplete(PerIoData);
        iotConnect:  RequestConnectComplete(Connection);
        iotReadZero: RequestReadZeroComplete(Connection, PerIoData);
        iotRead:     RequestReadComplete(Connection, PerIoData);
        iotWrite:    RequestWriteComplete(Connection, PerIoData);
      end;
    finally
      FreeIoData(PerIoData);
    end;
  except
    on e: Exception do
      AppendLog('%s.ProcessRequest, ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestAcceptComplete(PerIoData: PIocpPerIoData);
var
  Connection: TIocpSocketConnection;
  LocalAddrLen, RemoteAddrLen: Integer;
  LocalAddr, RemoteAddr: TSockaddr;
begin
  try
    // �����ӷŵ����������б���
    try
      FConnectionListLocker.Enter;
      Connection := FIdleConnectionList[PerIoData.ClientSocket];
      // ���֮ǰ�����Ӵ����ڿ��������б��������Ƶ����������б���
      if (Connection <> nil) then
      begin
        FConnectionList[PerIoData.ClientSocket] := Connection;
        FIdleConnectionList.Delete(Connection.FSocket);
      end else
      //** ��������Զ����ִ�е�������
      begin
        Connection := FConnectionList[PerIoData.ClientSocket];
        if (Connection = nil) then
        begin
          Connection := AllocConnection(PerIoData.ClientSocket);
          FConnectionList[PerIoData.ClientSocket] := Connection;
        end;
      end;

      // ��Socket���IOCP
      if not AssociateSocketWithCompletionPort(PerIoData.ClientSocket, Connection) then
      begin
        AppendLog('RequestAcceptComplete.AssociateSocketWithCompletionPort failed');
        Connection.Release;
        Exit;
      end;
    finally
      FConnectionListLocker.Leave;
    end;

    Connection.UpdateTick;

    // ����SO_UPDATE_ACCEPT_CONTEXT,���һ������optlenʵ����Ҫ�趨ΪSizeOf(PAnsiChar)
    // ��һ����MSDN�������ж��Ǵ�ģ���Ϊ����ʵ�ʲ��Է�����64λ���������ﴫ��SizeOf(PerIoData.ListenSocket)
    // �Ļ��ᱨ��10014,ϵͳ��⵽��һ�������г���ʹ��ָ�����ʱ����Чָ���ַ��
    // Ҳ����˵�����optlenʵ����Ӧ�ô��ݵ���һ��ָ��ĳ���
    if (setsockopt(PerIoData.ClientSocket, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT,
//      PAnsiChar(@(PerIoData.ListenSocket)), SizeOf(PerIoData.ListenSocket)) = SOCKET_ERROR) then
      PAnsiChar(@PerIoData.ListenSocket), SizeOf(PAnsiChar)) = SOCKET_ERROR) then
    begin
      AppendLog('%s.RequestAcceptComplete.setsockopt.SO_UPDATE_ACCEPT_CONTEXT ERROR %d=%s', [ClassName, WSAGetLastError, SysErrorMessage(WSAGetLastError)], ltWarning);
      Connection.Disconnect;
      Exit;
    end;

    // ��ȡ���ӵ�ַ��Ϣ
    LocalAddrLen := SizeOf(TSockAddr);
    RemoteAddrLen := SizeOf(TSockAddr);
    GetAcceptExSockaddrs(@PerIoData.Buffer.AcceptExBuffer[0], 0, SizeOf(TSockAddrIn) + 16,
      SizeOf(TSockAddrIn) + 16, LocalAddr, LocalAddrLen,
      RemoteAddr, RemoteAddrLen);

    if not Connection.InitSocket then
    begin
      Connection.Disconnect;
      Exit;
    end;

    // ������ַ��Ϣ
    Connection.FRemoteAddr := RemoteAddr;
    ExtractAddrInfo(Connection.FRemoteAddr, Connection.FRemoteIP, Connection.FRemotePort);

    // ��������������������Ͽ�
    if (FMaxClients > 0) and (FConnectionList.Count > FMaxClients) then
    begin
      Connection.Disconnect;
      Exit;
    end;

    if not _TriggerClientConnected(Connection) then Exit;

    // ���ӽ���֮��PostZero��ȡ����
    if not Connection.PostReadZero then Exit;
  except
    on e: Exception do
      AppendLog('%s.RequestAcceptComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestConnectComplete(Connection: TIocpSocketConnection);
begin
  try
    try
      if not Connection.InitSocket then
      begin
        Connection.Disconnect;
        Exit;
      end;

      try
        FConnectionListLocker.Enter;
        FConnectionList[Connection.FSocket] := Connection;
      finally
        FConnectionListLocker.Leave;
      end;

      Connection.UpdateTick;

      if not _TriggerClientConnected(Connection) then Exit;

      // ���ӽ���֮��PostZero��ȡ����
      if not Connection.PostReadZero then Exit;
    finally
      Connection.Release; // ��Ӧ AsyncConnect �е� AddRef;
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestConnectComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestReadZeroComplete(
  Connection: TIocpSocketConnection; PerIoData: PIocpPerIoData);
begin
  try
    try
      if (Connection.IsClosed) then Exit;

      Connection.UpdateTick;

      // ��ʽ��ʼ��������
      Connection.PostRead;
    finally
      Connection.Release; // ��ӦPostReadZero�е�AddRef
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestReadZeroComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestReadComplete(Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData);
begin
  try
    try
      Connection.DecPendingRecv;

      if (Connection.IsClosed) then Exit;

      if (PerIoData.BytesTransfered = 0) or (PerIoData.Buffer.DataBuf.buf = nil) then
      begin
        Connection.Disconnect;
        Exit;
      end;

      Connection.UpdateTick;

      // PerIoData.Buffer.DataBuf �����ѽ��յ������ݣ�PerIoData.BytesTransfered ��ʵ�ʽ��յ����ֽ���
      PerIoData.Buffer.DataBuf.Len := PerIoData.BytesTransfered;

      try
        InterlockedIncrement(FPendingRequest);
        if not _TriggerClientRecvData(Connection, PerIoData.Buffer.DataBuf.buf, PerIoData.Buffer.DataBuf.len) then Exit;
      finally
        InterlockedDecrement(FPendingRequest);
      end;

      // �������տͻ�������
      Connection.PostReadZero;
    finally
      Connection.Release; // ��ӦPostRead�е�AddRef
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestReadComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.RequestWriteComplete(Connection: TIocpSocketConnection;
  PerIoData: PIocpPerIoData);
begin
  try
    try
      Connection.DecPendingSend;

      if (Connection.IsClosed) then Exit;

      if (PerIoData.BytesTransfered = 0) or (PerIoData.Buffer.DataBuf.buf = nil) then
      begin
        Connection.Disconnect;
        Exit;
      end;

      Connection.UpdateTick;

      PerIoData.Buffer.DataBuf.Len := PerIoData.BytesTransfered;
      _TriggerClientSentData(Connection, PerIoData.Buffer.DataBuf.Buf, PerIoData.Buffer.DataBuf.Len);
    finally
      Connection.Release; // ��ӦPostWrite�е�AddRef
    end;
  except
    on e: Exception do
      AppendLog('%s.RequestWriteComplete ERROR %s=%s', [ClassName, e.ClassName, e.Message], ltException);
  end;
end;

procedure TIocpTcpSocket.SetConnectionClass(
  const Value: TIocpSocketConnectionClass);
begin
  FConnectionPool.ObjectClass := Value;
end;

procedure TIocpTcpSocket.CloseSocket(Socket: TSocket);
//var
//	lingerStruct: TLinger;
begin
{	lingerStruct.l_onoff := 1;
 lingerStruct.l_linger := 0;
 setsockopt(Socket, SOL_SOCKET, SO_LINGER, PAnsiChar(@lingerStruct), SizeOf(lingerStruct));
//  CancelIo(Socket);}

  IdWinsock2.shutdown(Socket, SD_BOTH);
  IdWinsock2.closesocket(Socket);
end;

procedure TIocpTcpSocket.StartupWorkers;
var
  si: TSystemInfo;
  NumberOfThreads, i: Integer;
begin
  if (FIocpHandle <> 0) then Exit;

  FPendingRequest := 0;

  // ����IO�߳���
  if (FIoThreadsNumber <= 0) then
  begin
    GetSystemInfo(si);
    NumberOfThreads := si.dwNumberOfProcessors * 2;
  end
  else
    NumberOfThreads := Min(FIoThreadsNumber, 64);

  // ������ɶ˿�
  // NumberOfConcurrentThreads = 0 ��ʾÿ��CPU����һ�������߳�
  FIocpHandle := IocpApiFix.CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  if (FIocpHandle = INVALID_HANDLE_VALUE) then
    raise Exception.CreateFmt('%s.StartupWorkers����IOCP����ʧ��', [ClassName]);

  // ����IO�߳�
  SetLength(FIoThreads, NumberOfThreads);
  SetLength(FIoThreadHandles, NumberOfThreads);
  for i := 0 to NumberOfThreads - 1 do
  begin
    FIoThreads[i] := TIocpIoThread.Create(Self);
    FIoThreadHandles[i] := FIoThreads[i].Handle;
  end;

  {$IFDEF __TIME_OUT_TIMER__}
  // ����ʱ�Ӷ���
  FTimerQueue := TIocpTimerQueue.Create;
  {$ENDIF}

  FSentBytes := 0;
  FRecvBytes := 0;
end;

procedure TIocpTcpSocket.ShutdownWorkers;
var
  i: Integer;
begin
  if (FIocpHandle = 0) then Exit;

  // �Ͽ���������
  DisconnectAll;

  {$IFDEF __TIME_OUT_TIMER__}
  // �ͷ�ʱ�Ӷ���
  FTimerQueue.Release;
  {$ENDIF}

  // ����������Sleep���Ա�֤���жϿ����ӵ�����Ⱥ����˳��̵߳������Ƚ���IOCP����
  // ������ܻ�������ӻ�ûȫ���ͷţ��߳̾ͱ���ֹ�ˣ������Դй©
  while ((FConnectionList.Count > 0) or (FIdleConnectionList.Count > 0)) do
    Sleep(10);

  // �رռ����߳�
  FListenThreadsLocker.Enter;
  try
    for i := 0 to FListenThreads.Count - 1 do
      TIocpAcceptThread(FListenThreads[i]).Quit;
    FListenThreads.Clear;
  finally
    FListenThreadsLocker.Leave;
  end;

  // �ر�IO�߳�
  for i := Low(FIoThreads) to High(FIoThreads) do
    IocpApiFix.PostQueuedCompletionStatus(FIocpHandle, 0, 0, POverlapped(SHUTDOWN_FLAG));

  // �ȴ�IO�߳̽���
  WaitForMultipleObjects(Length(FIoThreadHandles), Pointer(FIoThreadHandles), True, INFINITE);
  SetLength(FIoThreads, 0);
  SetLength(FIoThreadHandles, 0);

  // �ر���ɶ˿�
  CloseHandle(FIocpHandle);
  FIocpHandle := 0;

  FConnectionPool.Clear;
  FPerIoDataPool.Clear;

//  AppendLog('%s.shutdown compelte, ConnCount=%d, IdleConnCount=%d',
//    [ClassName, FConnectionList.Count, FIdleConnectionList.Count]);
end;

procedure TIocpTcpSocket.StopListen(ListenSocket: TSocket);
var
  i: Integer;
begin
  FListenThreadsLocker.Enter;
  try
    for i := 0 to FListenThreads.Count - 1 do
    begin
      if (ListenSocket = TIocpAcceptThread(FListenThreads[i]).ListenSocket) then
      begin
        TIocpAcceptThread(FListenThreads[i]).Quit;
        FListenThreads.Delete(i);
        Break;
      end;
    end;
  finally
    FListenThreadsLocker.Leave;
  end;
end;

function TIocpTcpSocket.TriggerClientConnected(
  Client: TIocpSocketConnection): Boolean;
begin
  if Assigned(FOnClientConnected) then
    Result := FOnClientConnected(Self, Client)
  else
    Result := True;
end;

function TIocpTcpSocket.TriggerClientDisconnected(
  Client: TIocpSocketConnection): Boolean;
begin
  if Assigned(FOnClientDisconnected) then
    Result := FOnClientDisconnected(Self, Client)
  else
    Result := True;
end;

function TIocpTcpSocket.TriggerClientRecvData(
  Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean;
begin
  if Assigned(FOnClientRecvData) then
    Result := FOnClientRecvData(Self, Client, Buf, Len)
  else
    Result := True;
end;

function TIocpTcpSocket.TriggerClientSentData(
  Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean;
begin
  if Assigned(FOnClientSentData) then
    Result := FOnClientSentData(Self, Client, Buf, Len)
  else
    Result := True;
end;

function TIocpTcpSocket._TriggerClientConnected(Client: TIocpSocketConnection): Boolean;
begin
  Result := TriggerClientConnected(Client);
end;

function TIocpTcpSocket._TriggerClientDisconnected(Client: TIocpSocketConnection): Boolean;
begin
  Result := TriggerClientDisconnected(Client);
end;

function TIocpTcpSocket._TriggerClientRecvData(Client: TIocpSocketConnection;
  Buf: Pointer; Len: Integer): Boolean;
begin
  DSiInterlockedExchangeAdd64(FRecvBytes, Len);
  Result := Client._TriggerClientRecvData(Buf, Len);
  if Result then
    Result := TriggerClientRecvData(Client, Buf, Len);
end;

function TIocpTcpSocket._TriggerClientSentData(Client: TIocpSocketConnection;
  Buf: Pointer; Len: Integer): Boolean;
begin
  DSiInterlockedExchangeAdd64(FSentBytes, Len);
  Result := Client._TriggerClientSentData(Buf, Len);
  if Result then
    Result := TriggerClientSentData(Client, Buf, Len);
end;

{ TIocpLineSocketConnection }

constructor TIocpLineSocketConnection.Create(AOwner: TObject);
begin
  inherited Create(AOwner);

  FLineText := TIocpStringStream.Create('');
end;

destructor TIocpLineSocketConnection.Destroy;
begin
  FLineText.Free;

  inherited Destroy;
end;

function TIocpLineSocketConnection.Send(const s: RawByteString): Integer;
begin
  Result := inherited Send(s + TIocpLineSocket(Owner).LineEndTag);
end;

{ TIocpLineSocket }

function TIocpLineSocket.Connect(const RemoteAddr: string; RemotePort: Word;
  Tag: Pointer; ConnectTimeout: DWORD): TIocpLineSocketConnection;
begin
  Result := TIocpLineSocketConnection(inherited Connect(RemoteAddr, RemotePort, Tag, ConnectTimeout));
end;

constructor TIocpLineSocket.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  ConnectionClass := TIocpLineSocketConnection;
  FLineEndTag := #13#10;
  FLineLimit := 65536;
end;

procedure TIocpLineSocket.DoOnRecvLine(Client: TIocpLineSocketConnection;
  Line: RawByteString);
begin
  if Assigned(FOnRecvLine) then
    FOnRecvLine(Self, Client, Line);
end;

procedure TIocpLineSocket.ParseRecvData(Client: TIocpLineSocketConnection;
  Buf: Pointer; Len: Integer);
var
  pch: PAnsiChar;
  Ch: AnsiChar;
  TagLen: Integer;
begin
  pch := Buf;
  TagLen := Length(FLineEndTag);
  while (Len > 0) do
  begin
    Ch := pch^;

    // ���ֻ��з�
    if (TagLen > 0) and (Len >= TagLen) and (StrLIComp(pch, PAnsiChar(FLineEndTag), TagLen) = 0) then
    begin
      if (Client.LineText.Size > 0) then
      begin
        DoOnRecvLine(Client, Client.LineText.DataString);
        Client.LineText.Clear;
      end;
      Dec(Len, TagLen);
      Inc(pch, TagLen);
      Continue;
    end;

    Client.LineText.Write(Ch, 1);

    // ��������гߴ�
    if (FLineLimit > 0) and (Client.LineText.Size >= FLineLimit) then
    begin
      DoOnRecvLine(Client, Client.LineText.DataString);
      Client.LineText.Clear;
    end;

    Dec(Len, SizeOf(Ch));
    Inc(pch);
  end;
end;

procedure TIocpLineSocket.SetLineEndTag(const Value: RawByteString);
begin
  if (Value <> '') then
    FLineEndTag := Value
  else
    FLineEndTag := #13#10;
end;

function TIocpLineSocket.TriggerClientRecvData(Client: TIocpSocketConnection;
  Buf: Pointer; Len: Integer): Boolean;
begin
  ParseRecvData(TIocpLineSocketConnection(Client), Buf, Len);
  Result := True;
end;

{ TIocpLineServer }

constructor TIocpLineServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FListenSocket := INVALID_SOCKET;
end;

function TIocpLineServer.Start: Boolean;
begin
  if (FListenSocket <> INVALID_SOCKET) then Exit(True);

  StartupWorkers;
  FListenSocket := inherited Listen(FAddr, FPort, 1);
  Result := (FListenSocket <> INVALID_SOCKET);
end;

function TIocpLineServer.Stop: Boolean;
begin
  if (FListenSocket = INVALID_SOCKET) then Exit(True);

  ShutdownWorkers;
  FListenSocket := 0;
  Result := True;
end;

{ TSimpleIocpTcpClient }

function TSimpleIocpTcpClient.AsyncConnect(Tag: Pointer): TSocket;
begin
  Result := inherited AsyncConnect(FServerAddr, FServerPort, Tag);
end;

function TSimpleIocpTcpClient.Connect(Tag: Pointer;
  ConnectTimeout: DWORD): TIocpSocketConnection;
begin
  Result := inherited Connect(FServerAddr, FServerPort, Tag, ConnectTimeout);
end;

{ TSimpleIocpTcpServer }

constructor TSimpleIocpTcpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FListenSocket := INVALID_SOCKET;

  FAddr := '';
  FInitAcceptNum := INIT_ACCEPTEX_NUM;
  FStartTick := 0;
end;

destructor TSimpleIocpTcpServer.Destroy;
begin
  Stop;
  inherited Destroy;
end;

function TSimpleIocpTcpServer.Start: Boolean;
begin
  if (FListenSocket <> INVALID_SOCKET) then Exit(True);

  StartupWorkers;
  FListenSocket := inherited Listen(FAddr, FPort, FInitAcceptNum);
  Result := (FListenSocket <> INVALID_SOCKET);
  if Result then
    FStartTick := GetTickCount;
end;

function TSimpleIocpTcpServer.Stop: Boolean;
begin
  if (FListenSocket = INVALID_SOCKET) then Exit(True);

  ShutdownWorkers;
  FListenSocket := INVALID_SOCKET;
  Result := True;
  FStartTick := 0;
end;

initialization
  IdWinsock2.InitializeWinSock;
  IdWship6.InitLibrary;

  IoCachePool := TIocpMemoryPool.Create(NET_CACHE_SIZE, MAX_FREE_IO_DATA_BLOCKS);
//  IoQueuePool := TIocpMemoryPool.Create(SizeOf(TIocpIoBlock), MAX_FREE_IO_DATA_BLOCKS);
  FileCachePool := TIocpMemoryPool.Create(FILE_CACHE_SIZE, MAX_FREE_HANDLE_DATA_BLOCKS);

finalization
  IoCachePool.Release;
//  IoQueuePool.Release;
  FileCachePool.Release;

  IdWinsock2.UninitializeWinSock;

end.

