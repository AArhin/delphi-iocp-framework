unit IocpPacketSocket;

interface

uses
  Windows, Classes, SysUtils, Math, JwaWinsock2, IocpTcpSocket, IocpLogger;

type
  TIocpHeader = record
    HeaderCrc32, DataCrc32: LongWord;
    Tick: LongWord;
    DataSize: Integer;
  end;

  TIocpPacket = record
    Header: TIocpHeader;
    Data: Pointer;
  end;

  // ʹ��Send(Stream)���ܻ�������Packet����
  TIocpPacketConnection = class(TIocpSocketConnection)
  private
    FRecvPacketBytes: Integer;
    FRecvPacket: TIocpPacket;

    function CalcHeaderCrc(const Header: TIocpHeader): LongWord;
    function PackData(Buf: Pointer; Len: Integer): TIocpPacket;
    function CheckHeaderCrc(const Header: TIocpHeader): Boolean;
    function CheckDataCrc(const Packet: TIocpPacket): Boolean;
  protected
    procedure Initialize; override;
  public
    function Send(Buf: Pointer; Size: Integer): Integer; override;
  end;

  TIocpPacketEvent = procedure(Sender: TObject; Client: TIocpPacketConnection; const Packet: TIocpPacket) of object;
  TIocpPacketSocket = class(TIocpTcpSocket)
  private
    FCrcEnabled: Boolean;
    FOnPacketRecv: TIocpPacketEvent;
    FOnPacketHeaderCrcError: TIocpPacketEvent;
    FOnPacketDataCrcError: TIocpPacketEvent;
  protected
    function TriggerClientRecvData(Client: TIocpSocketConnection; Buf: Pointer; Len: Integer): Boolean; override;

    procedure TriggerPacketRecv(Client: TIocpPacketConnection; const Packet: TIocpPacket); virtual;
    procedure TriggerPacketHeaderCrcError(Client: TIocpPacketConnection; const Packet: TIocpPacket); virtual;
    procedure TriggerPacketDataCrcError(Client: TIocpPacketConnection; const Packet: TIocpPacket); virtual;
  public
    constructor Create(AOwner: TComponent); overload; override;
  published
    property CrcEnabled: Boolean read FCrcEnabled write FCrcEnabled default True;
    property OnPacketRecv: TIocpPacketEvent read FOnPacketRecv write FOnPacketRecv;
    property OnPacketHeaderCrcError: TIocpPacketEvent read FOnPacketHeaderCrcError write FOnPacketHeaderCrcError;
    property OnPacketDataCrcError: TIocpPacketEvent read FOnPacketDataCrcError write FOnPacketDataCrcError;
  end;

  TIocpPacketServer = class(TIocpPacketSocket)
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
  published
    property Addr: string read FAddr write FAddr;
    property Port: Word read FPort write FPort;
    property InitAcceptNum: Integer read FInitAcceptNum write FInitAcceptNum default INIT_ACCEPTEX_NUM;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Iocp', [TIocpPacketSocket, TIocpPacketServer]);
end;

function CalcCrc32(const Buf; const BufSize: Integer): LongWord;
asm
      or eax, eax              // eax = Buf
      jz @fin
      or edx, edx              // edx = BufSize
      jbe @finz
      push esi
      mov esi, eax
      add esi, edx
      xor eax, eax
      xor ecx, ecx
    @l1:
      dec esi
      mov cl, [esi]
      add eax, ecx
      dec edx
      jnz @l1
      pop esi
    @fin:
      ret
    @finz:
      xor eax, eax
end;

{ TIocpPacketConnection }

procedure TIocpPacketConnection.Initialize;
begin
  inherited Initialize;
  FRecvPacketBytes := 0;
  ZeroMemory(@FRecvPacket, SizeOf(FRecvPacket));
end;

function TIocpPacketConnection.CalcHeaderCrc(const Header: TIocpHeader): LongWord;
begin
  Result := CalcCrc32((PAnsiChar(@Header) + SizeOf(Header.HeaderCrc32))^, SizeOf(Header) - SizeOf(Header.HeaderCrc32));
end;

function TIocpPacketConnection.PackData(Buf: Pointer;
  Len: Integer): TIocpPacket;
begin
  with Result do
  begin
    Header.DataCrc32 := CalcCrc32(Buf^, Len);
    Header.Tick := GetTickCount;
    Header.DataSize := Len;
    Data := Buf;
    Header.HeaderCrc32 := CalcHeaderCrc(Header);
  end;
end;

function TIocpPacketConnection.CheckHeaderCrc(const Header: TIocpHeader): Boolean;
begin
  Result := (CalcHeaderCrc(Header) = Header.HeaderCrc32);
end;

function TIocpPacketConnection.CheckDataCrc(const Packet: TIocpPacket): Boolean;
begin
  Result := (CalcCrc32(Packet.Data^, Packet.Header.DataSize) = Packet.Header.DataCrc32);
end;

function TIocpPacketConnection.Send(Buf: Pointer; Size: Integer): Integer;
var
  Packet: TIocpPacket;
begin
  Packet := PackData(Buf, Size);
  if (inherited Send(@Packet.Header, SizeOf(Packet.Header)) < 0) then Exit(-1);
  if (inherited Send(Packet.Data, Packet.Header.DataSize) < 0) then Exit(-2);

  Result := Size;
end;

{ TIocpPacketSocket }

constructor TIocpPacketSocket.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  ConnectionClass := TIocpPacketConnection;
  FCrcEnabled := True;
end;

function TIocpPacketSocket.TriggerClientRecvData(Client: TIocpSocketConnection;
  Buf: Pointer; Len: Integer): Boolean;
var
  p: PByte;
  r: Integer;
begin
  Result := True;

  with TIocpPacketConnection(Client) do
  begin
    // ��ͷ
    if (FRecvPacketBytes < SizeOf(TIocpHeader)) then
    begin
      p := @FRecvPacket.Header;
      Inc(p, FRecvPacketBytes);
      r := Min(SizeOf(TIocpHeader) - FRecvPacketBytes, Len);
      CopyMemory(p, Buf, r);
      Inc(FRecvPacketBytes, r);

      // �����ͷ��һ���ְ���һ����յ�
      // �ݹ�һ�½�ʣ��Ĳ���д��FRecvPacket.Data��
      if (Len > r) then
      begin
        p := Buf;
        Inc(p, r);
        TriggerClientRecvData(Client, p, Len - r);
      end;
    end else
    // ����
    begin
      // �����Ƿ���CrcEnabled���أ�������У���ͷ
      // ����ܱ�֤�յ�������Ч���������ǲ��ɿ���Դ������������
      if not CheckHeaderCrc(FRecvPacket.Header) then
      begin
        TriggerPacketHeaderCrcError(TIocpPacketConnection(Client), FRecvPacket);
        Client.Disconnect;
        Exit;
      end;

      if (FRecvPacket.Data = nil) then
      begin
        try
          GetMem(FRecvPacket.Data, FRecvPacket.Header.DataSize);
        except
          AppendLog('%s.TriggerClientRecvData �����ڴ��ʧ�ܣ���С = %d�ֽ�', [Self.ClassName, FRecvPacket.Header.DataSize], ltWarning);
          Client.Disconnect;
          Exit;
        end;
      end;
      p := FRecvPacket.Data;
      Inc(p, FRecvPacketBytes - SizeOf(TIocpHeader));
      r := Min(Len, SizeOf(TIocpHeader) + FRecvPacket.Header.DataSize - FRecvPacketBytes);
      CopyMemory(p, Buf, r);
      Inc(FRecvPacketBytes, r);

      if (FRecvPacketBytes >= SizeOf(TIocpHeader) + FRecvPacket.Header.DataSize) then
      begin
        if FCrcEnabled and not CheckDataCrc(FRecvPacket) then
        begin
          TriggerPacketDataCrcError(TIocpPacketConnection(Client), FRecvPacket);
          Client.Disconnect;
          Exit;
        end;

        // һ������ȷ�������պ󣬴����¼�
        TriggerPacketRecv(TIocpPacketConnection(Client), FRecvPacket);

        FRecvPacketBytes := 0;
        FreeMem(FRecvPacket.Data);
        FRecvPacket.Data := nil;

        // ���������һ�������İ�֮����ʣ������
        // �ݹ��������
        if (Len > r) then
        begin
          p := Buf;
          Inc(p, r);
          TriggerClientRecvData(Client, p, Len - r);
        end;
      end;
    end;
  end;
end;

procedure TIocpPacketSocket.TriggerPacketRecv(Client: TIocpPacketConnection;
  const Packet: TIocpPacket);
begin
  if Assigned(FOnPacketRecv) then
    FOnPacketRecv(Self, Client, Packet);
end;

procedure TIocpPacketSocket.TriggerPacketHeaderCrcError(Client: TIocpPacketConnection;
  const Packet: TIocpPacket);
begin
  if Assigned(FOnPacketHeaderCrcError) then
    FOnPacketHeaderCrcError(Self, Client, Packet);
end;

procedure TIocpPacketSocket.TriggerPacketDataCrcError(
  Client: TIocpPacketConnection; const Packet: TIocpPacket);
begin
  if Assigned(FOnPacketDataCrcError) then
    FOnPacketDataCrcError(Self, Client, Packet);
end;

{ TIocpPacketServer }

constructor TIocpPacketServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FListenSocket := INVALID_SOCKET;

  FAddr := '';
  FInitAcceptNum := INIT_ACCEPTEX_NUM;
  FStartTick := 0;
end;

destructor TIocpPacketServer.Destroy;
begin
  Stop;
  inherited Destroy;
end;

function TIocpPacketServer.Start: Boolean;
begin
  if (FListenSocket <> INVALID_SOCKET) then Exit(True);

  StartupWorkers;
  FListenSocket := inherited Listen(FAddr, FPort, FInitAcceptNum);
  Result := (FListenSocket <> INVALID_SOCKET);
  if Result then
    FStartTick := GetTickCount;
end;

function TIocpPacketServer.Stop: Boolean;
begin
  if (FListenSocket = INVALID_SOCKET) then Exit(True);

  ShutdownWorkers;
  FListenSocket := INVALID_SOCKET;
  Result := True;
  FStartTick := 0;
end;

end.
