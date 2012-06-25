unit IocpMemoryPool;

//{$define __ZERO_MEMORY__}
{$DEFINE __HEAP_ALLOC__}

interface

uses
  Windows, Classes, SysUtils, SyncObjs, IocpLogger;

type
  TIocpMemoryPool = class
  private
    FRefCount: Integer;
    {$IFDEF __HEAP_ALLOC__}
    FHeapHandle: THandle;
    {$ENDIF}
    FBlockSize, FMaxFreeBlocks: Integer;
    FFreeMemoryBlockList: TList; // ����ʵ�ʲ��ԣ�ʹ��Classes.TList��Collections.TList<>Ч�ʸ���
    FUsedMemoryBlockList: TList;
    FLocker: TCriticalSection;

    function GetFreeBlocks: Integer;
    function GetFreeBlocksSize: Integer;
    function GetUsedBlocks: Integer;
    function GetUsedBlocksSize: Integer;
    procedure SetMaxFreeBlocks(MaxFreeBlocks: Integer);
  public
    constructor Create(BlockSize, MaxFreeBlocks: Integer); virtual;
    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;
    function AddRef: Integer;
    function Release: Boolean;
    function GetMemory: Pointer;
    procedure FreeMemory(var P: Pointer);
    procedure Clear;

    property FreeMemoryBlockList: TList read FFreeMemoryBlockList;
    property UsedMemoryBlockList: TList read FUsedMemoryBlockList;
    property BlockSize: Integer read FBlockSize;
    property FreeBlocks: Integer read GetFreeBlocks;
    property FreeBlocksSize: Integer read GetFreeBlocksSize;
    property UsedBlocks: Integer read GetUsedBlocks;
    property UsedBlocksSize: Integer read GetUsedBlocksSize;
    property MaxFreeBlocks: Integer read FMaxFreeBlocks write SetMaxFreeBlocks;
  end;

implementation

{ TIocpMemoryPool }

constructor TIocpMemoryPool.Create(BlockSize, MaxFreeBlocks: Integer);
begin
  // ���С��64�ֽڶ��룬������ִ��Ч�����
  if (BlockSize mod 64 = 0) then
    FBlockSize := BlockSize
  else
    FBlockSize := (BlockSize div 64) * 64 + 64;
    
  FMaxFreeBlocks := MaxFreeBlocks;
  FFreeMemoryBlockList := TList.Create;
  FUsedMemoryBlockList := TList.Create;
  FLocker := TCriticalSection.Create;
  {$IFDEF __HEAP_ALLOC__}
  FHeapHandle := GetProcessHeap;
  {$ENDIF}
  FRefCount := 1;
end;

destructor TIocpMemoryPool.Destroy;
begin
  Clear;

  FFreeMemoryBlockList.Free;
  FUsedMemoryBlockList.Free;
  FLocker.Free;
  
  inherited Destroy;
end;

procedure TIocpMemoryPool.Lock;
begin
  FLocker.Enter;
end;

procedure TIocpMemoryPool.Unlock;
begin
  FLocker.Leave;
end;

function TIocpMemoryPool.AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TIocpMemoryPool.Release: Boolean;
begin
  Result := (InterlockedDecrement(FRefCount) = 0);
  if Result then Free;
end;

function TIocpMemoryPool.GetMemory: Pointer;
begin
  Lock;
  try
    Result := nil;

    // �ӿ����ڴ���б���ȡһ��
    if (FFreeMemoryBlockList.Count > 0) then
    begin
      Result := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
    end;

    // ���û�п����ڴ�飬�����µ��ڴ��
    if (Result = nil) then
    begin
      {$IFDEF __HEAP_ALLOC__}
      Result := HeapAlloc(FHeapHandle, 0, FBlockSize);
      {$ELSE}
      Result := Pointer(GlobalAlloc(GPTR, FBlockSize));
      {$ENDIF}
      AddRef;
    end;

    if (Result <> nil) then
    begin
      {$ifdef __ZERO_MEMORY__}
      // �����ڴ��
      ZeroMemory(Result, FBlockSize);
      {$endif}
      // ��ȡ�õ��ڴ�������ʹ���ڴ���б�
      FUsedMemoryBlockList.Add(Result);
    end else
      raise Exception.CreateFmt('�����ڴ��ʧ�ܣ����С: %d', [FBlockSize]);
  finally
    Unlock;
  end;
end;

procedure TIocpMemoryPool.FreeMemory(var P: Pointer);
begin
  if (P = nil) then Exit;

  Lock;
  try
    // ����ʹ���ڴ���б����Ƴ��ڴ��
    if (FUsedMemoryBlockList.Extract(P) = nil) then Exit;

    // ����������ڴ��û�г��꣬���ڴ��ŵ������ڴ���б���
    if (FFreeMemoryBlockList.Count < FMaxFreeBlocks) then
      FFreeMemoryBlockList.Add(P)
    // �����ͷ��ڴ�
    else
    begin
      {$IFDEF __HEAP_ALLOC__}
      HeapFree(FHeapHandle, 0, P);
      {$ELSE}
      GlobalFree(HGLOBAL(P));
      {$ENDIF}
      Release;
    end;

    P := nil;
  finally
    Unlock;
  end;
end;

procedure TIocpMemoryPool.Clear;
var
  P: Pointer;
begin
  Lock;
  try
    // ��տ����ڴ�
    while (FFreeMemoryBlockList.Count > 0) do
    begin
      P := FFreeMemoryBlockList[FFreeMemoryBlockList.Count - 1];
      if (P <> nil) then
        {$IFDEF __HEAP_ALLOC__}
        HeapFree(FHeapHandle, 0, P);
        {$ELSE}
        GlobalFree(HGLOBAL(P));
        {$ENDIF}
      FFreeMemoryBlockList.Delete(FFreeMemoryBlockList.Count - 1);
      Release;
    end;

    // �����ʹ���ڴ�
    while (FUsedMemoryBlockList.Count > 0) do
    begin
      P := FUsedMemoryBlockList[FUsedMemoryBlockList.Count - 1];
      if (P <> nil) then
        {$IFDEF __HEAP_ALLOC__}
        HeapFree(FHeapHandle, 0, P);
        {$ELSE}
        GlobalFree(HGLOBAL(P));
        {$ENDIF}
      FUsedMemoryBlockList.Delete(FUsedMemoryBlockList.Count - 1);
      Release;
    end;
  finally
    Unlock;
  end;
end;

function TIocpMemoryPool.GetFreeBlocks: Integer;
begin
  Result := FFreeMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetFreeBlocksSize: Integer;
begin
  Result := FFreeMemoryBlockList.Count * FBlockSize;
end;

function TIocpMemoryPool.GetUsedBlocks: Integer;
begin
  Result := FUsedMemoryBlockList.Count;
end;

function TIocpMemoryPool.GetUsedBlocksSize: Integer;
begin
  Result := FUsedMemoryBlockList.Count * FBlockSize;
end;

procedure TIocpMemoryPool.SetMaxFreeBlocks(MaxFreeBlocks: Integer);
begin
  Lock;
  FMaxFreeBlocks := MaxFreeBlocks;
  Unlock;
end;

end.
