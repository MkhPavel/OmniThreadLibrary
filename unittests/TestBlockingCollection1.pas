unit TestBlockingCollection1;

interface

{$IFDEF Unicode}
uses
  TestFramework, GpStuff, Windows, DSiWin32, OtlContainers, SysUtils,
  OtlContainerObserver, OtlCollections, OtlCommon, OtlSync;

type
  // Test methods for class IOmniBlockingCollection
  TestIOmniBlockingCollection = class(TTestCase)
  private
    procedure FillOmniValueWithOwnedObject(VAR lValue:TOmniValue);
  published
    procedure TestCompleteAdding;
    procedure TestOwnedObjectleak;
    procedure TestOmniValueObjectleak;
    procedure TestInterfaceLeak;
    procedure TestIsEmpty;
  end;

  TestCollectionOf = class(TTestCase)
  published
    procedure TestIntegerData;
    procedure TestIntegerDataEnumerator;
    procedure TestInterfaceData;
    procedure TestInterfaceDataEnumerator;
  end;
{$ENDIF}

implementation

{$IFDEF Unicode}
uses
  OtlParallel,
  Classes;

type
  TMemLeakCheckObj=class(TInterfacedObject)
    constructor Create;
    destructor Destroy; override;
  end;

var
  vMemLeakCheckObjCount: integer = 0;

procedure TestIOmniBlockingCollection.TestCompleteAdding;
var
  coll     : IOmniBlockingCollection;
  iTest    : integer;
  lastAdded: integer;
  lastRead : TOmniValue;
begin
  for iTest := 1 to 1000 do begin
    coll := TOmniBlockingCollection.Create;
    lastAdded := -1;
    lastRead := -2;
    Parallel.Join([
      procedure
      var
        i: integer;
      begin
        for i := 1 to 100000 do begin
          if not coll.TryAdd(i) then
            break;
          lastAdded := i;
        end;
      end,

      procedure
      begin
        Sleep(1);
        coll.CompleteAdding;
      end,

      procedure
      begin
        while coll.TryTake(lastRead, INFINITE) do
          ;
      end
    ]).Execute;
    if (lastAdded > 0) and (lastRead.AsInteger > 0) and (lastAdded <> lastRead.AsInteger) then
      break; //for iTest
  end;
  CheckEquals(lastAdded, lastRead.AsInteger);
end;

{ TMemLeakCheckObj }

constructor TMemLeakCheckObj.Create;
begin
  InterlockedIncrement(vMemLeakCheckObjCount);
  inherited;
end;

destructor TMemLeakCheckObj.Destroy;
begin
  inherited;
  InterlockedDecrement(vMemLeakCheckObjCount);
end;

procedure TestIOmniBlockingCollection.TestInterfaceLeak;
const cTestSize=10;
VAR i:integer;
    lCollection:IOmniBlockingCollection;
    lValue:TOmniValue;
begin
  lCollection := TOmniBlockingCollection.Create;
  vMemLeakCheckObjCount := 0;
  for i := 1 to cTestSize do begin
    lValue.AsInterface := TMemLeakCheckObj.Create;
    lCollection.Add(lValue);
  end;
  lValue.Clear;
  CheckEquals(cTestSize,vMemLeakCheckObjCount);
  for i := 1 to cTestSize do
    lCollection.Take(lValue);
  lCollection := nil;

  CheckEquals(1, vMemLeakCheckObjCount);
  lValue.Clear; // drop the last interface in the queue
  CheckEquals(0, vMemLeakCheckObjCount);
end;

//Using a separate routine to set the AsOwnedObject property is required because
//the compiler generates code that keeps the last created object alive (refcount) until the
//routine is actually finished
procedure TestIOmniBlockingCollection.FillOmniValueWithOwnedObject(var lValue: TOmniValue);
begin
  lValue.AsOwnedObject := TMemLeakCheckObj.Create;
end;

procedure TestIOmniBlockingCollection.TestIsEmpty;
const
  CNumSlots = 4096; //initialized in TOmniBaseQueue<T>.Create [obcNumSlots]
var
  coll: IOmniBlockingCollection;
  i   : integer;
  val : TOmniValue;
begin
  coll := TOmniBlockingCollection.Create;
  CheckTrue(coll.IsEmpty);
  coll.Add(1);
  CheckFalse(coll.IsEmpty);
  coll.Take(val);
  CheckTrue(coll.IsEmpty);
  for i := 2 to CNumSlots - 3 do // one value was already added, three slots are used for internal purposes
    coll.Add(1);
  CheckFalse(coll.IsEmpty);
  //Next Add will trigger memory allocation
  coll.Add(1);
  CheckFalse(coll.IsEmpty);
  for i := 2 to CNumSlots - 3 do
    coll.Take(val);
  CheckFalse(coll.IsEmpty);
  //Next Take will follow block pointer
  coll.Take(val);
  CheckTrue(coll.IsEmpty);
end;

procedure TestIOmniBlockingCollection.TestOmniValueObjectleak;
VAR lValue:TOmniValue;
begin
  vMemLeakCheckObjCount := 0;
  FillOmniValueWithOwnedObject(lValue);
  CheckEquals(1, vMemLeakCheckObjCount);
  lValue.Clear; // one would expect the owned object to be destroyed here, but it does NOT

  CheckEquals(0, vMemLeakCheckObjCount); // this test Fails
end;

procedure TestIOmniBlockingCollection.TestOwnedObjectleak;
const
  cTestSize = 10;
var
  i          : integer;
  lCollection: IOmniBlockingCollection;
  lValue     : TOmniValue;

begin
  lCollection := TOmniBlockingCollection.Create;
  vMemLeakCheckObjCount := 0;
  for i := 1 to cTestSize do begin
    FillOmniValueWithOwnedObject(lValue);
    lCollection.Add(lValue);
  end;
  lValue.Clear;
  CheckEquals(cTestSize, vMemLeakCheckObjCount);

  for i := 1 to cTestSize do
    lCollection.Take(lValue);
  lCollection := nil;

  CheckEquals(1, vMemLeakCheckObjCount);

  // drop the last owned object in the queue
  lValue.Clear; // drop the last owned object in the queue

  // this test fails for some strange reason, obviously the lValue is not
  // released until the end of the routine eventhough it is actually cleared
  CheckEquals(0, vMemLeakCheckObjCount);
end;

{ TestCollectionOf }

procedure TestCollectionOf.TestIntegerData;
var
  coll : TOmniBlockingCollection<integer>;
  i    : integer;
  value: integer;
begin
  coll := TOmniBlockingCollection<integer>.Create;
  try
    for i := 1 to 65536 do
      coll.Add(i);
    coll.CompleteAdding;
    for i := 1 to 65536 do begin
      CheckTrue(coll.Take(value));
      CheckEquals(i, value);
    end;
    CheckTrue(coll.IsEmpty);
    CheckFalse(coll.Take(value));
  finally FreeAndNil(coll); end;
end;

procedure TestCollectionOf.TestIntegerDataEnumerator;
var
  coll : TOmniBlockingCollection<integer>;
  i    : integer;
  value: integer;
begin
  coll := TOmniBlockingCollection<integer>.Create;
  try
    for i := 1 to 65536 do
      coll.Add(i);
    coll.CompleteAdding;
    i := 0;
    for value in coll do begin
      Inc(i);
      CheckEquals(value, i);
    end;
    CheckEquals(i, 65536);
  finally FreeAndNil(coll); end;
end;

procedure TestCollectionOf.TestInterfaceData;
var
  coll : TOmniBlockingCollection<IOmniCounter>;
  i    : integer;
  value: IOmniCounter;
begin
  coll := TOmniBlockingCollection<IOmniCounter>.Create;
  try
    for i := 1 to 65536 do
      coll.Add(CreateCounter(i));
    coll.CompleteAdding;
    for i := 1 to 65536 do begin
      CheckTrue(coll.Take(value));
      CheckEquals(i, value.Value);
    end;
    CheckTrue(coll.IsEmpty);
    CheckFalse(coll.Take(value));
  finally FreeAndNil(coll); end;
end;

procedure TestCollectionOf.TestInterfaceDataEnumerator;
var
  coll : TOmniBlockingCollection<IOmniCounter>;
  i    : integer;
  value: IOmniCounter;
begin
  coll := TOmniBlockingCollection<IOmniCounter>.Create;
  try
    for i := 1 to 65536 do
      coll.Add(CreateCounter(i));
    coll.CompleteAdding;
    i := 0;
    for value in coll do begin
      Inc(i);
      CheckEquals(value.Value, i);
    end;
    CheckEquals(i, 65536);
  finally FreeAndNil(coll); end;
end;

initialization
  // Register any test cases with the test runner
  RegisterTest(TestIOmniBlockingCollection.Suite);
  RegisterTest(TestCollectionOf.Suite);
{$ENDIF}
end.

