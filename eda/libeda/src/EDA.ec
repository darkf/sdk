#ifdef ECERE_STATIC
public import static "ecere"
#else
public import "ecere"
#endif

public enum OpenType { queryRows, tableRows, viewRows, processesList, databasesList, tablesList, fieldsList };
public enum CreateOptions { no, create, readOnly };
public enum AccessOptions { integral, random };
public enum SeekOptions { none, reset, first, last, firstEqual, lastEqual };
public enum MoveOptions { nil, first, last, next, previous, middle, here };
public enum MatchOptions { nil };
public enum ObjectType { table, view };
public enum State { none, driver, connected, opened, closed, errorDriver };

#define AUTO_DELETE
#define AUTO_DELETE_TABLES

public class OpenOptions : uint
{
public:
   OpenType type:8;
   CreateOptions create:2;
   AccessOptions access:2;
};

public class DataSourceDriver
{
   OldList listDB { offset = (uint)&((Database)0).prev };
   class_data char * name;

   class_property char * name
   {
      set { class_data(name) = value; }
      get { return class_data(name); }
   }

public:
   virtual String BuildLocator(DataSource ds);
   virtual uint GetDatabasesCount();
   virtual bool Connect(const String locator);
   virtual void Status();
   virtual bool RenameDatabase(const String name, const String rename);
   virtual bool DeleteDatabase(const String name);
   virtual Database OpenDatabase(const String name, CreateOptions create, DataSource ds);

   ~DataSourceDriver()
   {
      Database db;
      while((db = listDB.first))
      {
         listDB.Remove(db);
         db.ds = null;
         delete db;
      };
   }
}

static subclass(DataSourceDriver) GetDataDriver(char * driverName)
{
   subclass(DataSourceDriver) driver = null;
   driver = FindDataDriverDerivative(class(DataSourceDriver), driverName);
   if(!driver)
   {
      Module module;
      char moduleName[MAX_LOCATION];
      sprintf(moduleName, "EDA%s", driverName);
      if(module = eModule_Load(__thisModule.application, moduleName, publicAccess))
         driver = FindDataDriverDerivative(eSystem_FindClass(module /*__thisModule.application*/, "DataSourceDriver"), driverName);
   }
   return driver;
}

static subclass(DataSourceDriver) FindDataDriverDerivative(Class dataSourceDriverClass, char * driverName)
{
   OldLink link;
   subclass(DataSourceDriver) derivative = null;
   for(link = dataSourceDriverClass.derivatives.first; link; link = link.next)
   {
      subclass(DataSourceDriver) dataDriver = link.data;
      Class driverClass = link.data;
      if(dataDriver.name && !strcmp(dataDriver.name, driverName))
      {
         derivative = dataDriver;
         break;
      }
      if(driverClass.derivatives.first && (derivative = FindDataDriverDerivative(driverClass, driverName)))
         break;
   }
   return derivative;
}

public class DataSource
{
   DataSourceDriver ds;
   String host;
   String port;
   String user;
   String pass;
   String locator;
   
   ~DataSource()
   {
      delete locator;
      delete ds;
      delete host;
      delete port;
      delete user;
      delete pass;
   }

public:
   property String driver
   {
      get { return ds ? ((subclass(DataSourceDriver))(ds._class)).name : null; }
      set { delete ds; ds = value ? eInstance_New(GetDataDriver(value)) : null; }
   }
   property String host
   {
      set { delete host; host = CopyString(value); }
      get { return host; }
   }
   property String port
   {
      set { delete port; port = CopyString(value); }
      get { return port; }
   }
   property String user
   {
      set { delete user; user = CopyString(value); }
      get { return user; }
   }
   property String pass
   {
      set { delete pass; pass = CopyString(value); }
      get { return pass; }
   }
   property String locator
   {
      set
      {
         delete host;
         delete port;
         delete user;
         delete pass;
         delete locator;
         locator = CopyString(value);
      }
      get { return locator; }
   }

   property uint databasesCount { get { return ds.GetDatabasesCount(); } }
   bool Connect()
   {
      if(!locator && ds)
      {
         if(host || port || user || pass)
         {
            delete locator;
            locator = ds.BuildLocator(this);
         }
      }
      return ds ? ds.Connect(locator) : false;
   }
   void Status() { ds.Status(); }
   bool RenameDatabase(const String name, const String rename) { return ds.RenameDatabase(name, rename); }
   bool DeleteDatabase(const String name) { return ds.DeleteDatabase(name); }
   Database OpenDatabase(const String name, CreateOptions create)
   {
      Database db = ds.OpenDatabase(name, create, this);
      if(db)
      {
         ds.listDB.Add(db);
         db.ds = ds;
      }
      return db;
   }
}

public class Database
{
   Database prev, next;
   DataSourceDriver ds;
   OldList listTbl { offset = (uint)&((Table)0).prev };
   public virtual String GetName();

   ~Database()
   {
      Table tbl;
      if(ds)
         ds.listDB.Remove(this);
      while((tbl = listTbl.first))
      {
         listTbl.Remove(tbl);
         tbl.db = null;
         delete tbl;
      };
   }
   public void LinkTable(Table tbl)
   {
#ifdef AUTO_DELETE_TABLES
      listTbl.Add(tbl);
#endif
      tbl.db = this;
   }

public:
   property String name { get { return GetName(); } }
   property uint tablesCount { get { return ObjectsCount(table); } }
   property uint viewsCount { get { return ObjectsCount(view); } }

   virtual uint ObjectsCount(ObjectType type);
   virtual bool RenameObject(ObjectType type, const String name, const String rename);
   virtual bool DeleteObject(ObjectType type, const String name);
   virtual Table OpenTable(const String name, OpenOptions open);
   virtual bool Begin();
   virtual bool Commit();
   virtual bool CreateCustomFunction(char * name, SQLCustomFunction customFunction);
}

public enum IndexOrder { ascending, descending };

public struct FieldIndex
{
   Field field;
   IndexOrder order;
   Field memberField;
   Table memberTable;
   Field memberIdField;
};

public class Table
{
   Table prev, next;
   Database db;
   OldList listRows { offset = (uint)&((Row)0).prev };
public:
   virtual String GetName();
   virtual Field GetFirstField();
   virtual uint GetFieldsCount();
   virtual uint GetRowsCount();
   virtual DriverRow CreateRow();

   ~Table()
   {
      Row row;
#ifdef AUTO_DELETE_TABLES
      if(db)
         db.listTbl.Remove(this);
#endif
      while((row = listRows.first))
         row.tbl = null;
   }
public:
   property String name { get { return GetName(); } }
   property Field firstField { get { return GetFirstField(); } }
   property uint fieldsCount { get { return GetFieldsCount(); } }
   property uint rowsCount { get { return GetRowsCount(); } }
   
   virtual Field AddField(const String name, Class type, int length);
   virtual Field FindField(const String name);
   virtual bool GenerateIndex(int count, FieldIndex * fieldIndexes, bool init);
   bool Index(int count, FieldIndex * fieldIndexes)
   {
      return GenerateIndex(count, fieldIndexes, true);
   }

   void GUIListBoxAddRowsField(ListBox list, const String fieldName)
   {
      Field fld;
      list.Clear();
      fld = FindField(fieldName);
      if(fld)
      {
         Row r { this };
         while(r.Next())
         {
            String s/* = null*/;
            r.GetData(fld, s);
            list.AddRow().SetData(null, s);
            delete s;
         }
         delete r;
      }
   }

   void GUIListBoxAddFields(ListBox list)
   {
      Field fld;
      list.Clear();
      list.ClearFields();
      for(fld = firstField; fld; fld = fld.next)
      {
         DataField df
         {
            alignment = left;
            dataType = fld.type;
            editable = true;
            header = fld.name;
            width = 100;
         };         
         list.AddField(df);
      }
   }

   void GUIListBoxAddRows(ListBox list)
   {
      list.Clear();
      if(rowsCount)
      {
         DataField df;
         DataRow dr;
         Row r { this };
         dr = list.firstRow;
         while(r.Next())
         {
            Field fld = firstField;
            for(df = list.firstField; df; df = df.next, fld = fld.next)
            {
               int64 data = 0;
               Class type = fld.type;
               if(type.type == unitClass && !type.typeSize)
               {
                  Class dataType = eSystem_FindClass(type.module, type.dataTypeString);
                  if(dataType)
                     type = dataType;
               }
               if(type.type == structClass)
                  data = (int64)new0 byte[type.structSize];
               if(!df.prev)
               {
                  dr = list.AddRow();
                  dr.tag = r.sysID;
               }
               ((bool (*)())(void *)r.GetData)(r, fld, type, (type.type == structClass) ? (void *)data : &data);
               if(type.type == systemClass || type.type == unitClass || type.type == bitClass || type.type == enumClass)
                  dr.SetData(df, (void *)&data);
               else
                  dr.SetData(df, (void *)data);

               // Is this missing some frees here? strings? Probably not: freeData = true?
               // type._vTbl[__ecereVMethodID_class_OnFree](type, data);
               if(type.type == structClass)
               {
                  void * dataPtr = (void *)data;
                  delete dataPtr;
               }
               else if(!strcmp(type.dataTypeString, "char *"))
               {
                  // Strings are handled as a special case in ListBox -- normalClass, but copied when freeData = true
                  char * string = (char *)data;
                  delete string;
               }
            }
            dr = dr.next;
         }
         delete r;
      }
   }
}

public class Field
{
   class_no_expansion
public:
   virtual String GetName();
   virtual Class GetType();
   virtual int GetLength();
   virtual Field GetPrev();
   virtual Field GetNext();

   property String name { get { return GetName(); } }
   property Class type { get { return GetType(); } }
   property int length { get { return GetLength(); } }
   property Field prev { get { return GetPrev(); } }
   property Field next { get { return GetNext(); } }

   bool GetData(Row row, typed_object & data)
   {
      return row.GetData(this, data);
   }

   bool SetData(Row row, typed_object & data)
   {
      return row.SetData(this, data);
   }
};

public class Row
{
   DriverRow row;
   Row prev, next;
   Table tbl;

   ~Row()
   {
#ifdef AUTO_DELETE
      if(tbl)
         tbl.listRows.Remove(this);
#endif
      delete row;
   }

public:
   property Table tbl
   {
      set
      {
         delete row;
         row = value ? value.CreateRow() : null;
         if(tbl)
         {
#ifdef AUTO_DELETE
            tbl.listRows.Remove(this);
#endif
            tbl = value;
            if(!value)
            {
               delete this;
               return;
            }
         }
         if(value)
         {
#ifdef AUTO_DELETE
            if(!tbl)
               incref this;
#endif
            tbl = value;
#ifdef AUTO_DELETE
            tbl.listRows.Add(this);
#endif
         }         
      }
      get { return tbl; }
   }

   property bool nil { get { return row ? row.Nil() : true; } }

   property char * query { set { if(row) row.Query(value); } }

   public bool Query(char * query)  // Add printf format support
   {
      if(row)
         return row.Query(query);
      return false;
   }
   bool Select(MoveOptions move) { return row ? row.Select(move) : false; }
   bool First() { return row ? row.Select(first) : false; }
   bool Last() { return row ? row.Select(last) : false; }
   bool Next() { return row ? row.Select(next) : false; }
   bool Previous() { return row ? row.Select(previous) : false; }

   bool Find(Field field, MoveOptions move, MatchOptions match, typed_object data) { return (row && field) ? row.Find(field, move, match, data) : false; }
   bool FindMultiple(FieldFindData * findData, MoveOptions move, int numFields) { return row ? row.FindMultiple(findData, move, numFields) : false; }

   bool Synch(Row to) { return row && to && row._class == to.row._class ? row.Synch(to.row) : false; }

   bool Add() { return row ? row.Add(0) : false; }
   bool AddID(uint64 id) { return row ? row.Add(id) : false; }
   bool GetData(Field field, typed_object & data) { return (row && field) ? row.GetData(field, data) : false; }
   bool SetData(Field field, typed_object data) { return (row && field) ? row.SetData(field, data) : false; }
   bool Delete() { return row ? row.Delete() : false; }
   // TODO: Implement as a typed_object?
   bool SetQueryParam(int paramID, int value) { return row ? row.SetQueryParam(paramID, value) : false; }
   bool SetQueryParam64(int paramID, int64 value) { return row ? row.SetQueryParam64(paramID, value) : false; }   
   bool SetQueryParamText(int paramID, char * value) { return row ? row.SetQueryParamText(paramID, value) : false; }
   bool SetQueryParamObject(int paramID, void * value, Class type) { return row ? row.SetQueryParamObject(paramID, value, type) : false; }
   char * GetColumn(int paramID) { return row ? row.GetColumn(paramID) : null; }

   bool GUIDataRowSetData(DataRow dr, DataField df, Field fld)
   {
      int64 data = 0;
      Class type = fld.type;
      if(type.type == unitClass && !type.typeSize)
      {
         Class dataType = eSystem_FindClass(type.module, type.dataTypeString);
         if(dataType)
            type = dataType;
      }
      if(type.type == structClass)
         data = (int64)new0 byte[type.structSize];
      ((bool (*)())(void *)GetData)(this, fld, type, (type.type == structClass) ? (void *)data : &data);

      if((type.type == systemClass || type.type == unitClass || type.type == bitClass || type.type == enumClass))
         dr.SetData(df, (void *)&data);
      else
         dr.SetData(df, (void *)data);
      if(type.type == structClass)
      {
         void * dataPtr = (void *)data;
         delete dataPtr;
      }
      else if(!strcmp(type.dataTypeString, "char *"))
      {
         // Strings are handled as a special case in ListBox -- normalClass, but copied when freeData = true
         char * string = (char *)data;
         delete string;
      }
   }

   property uint sysID { get { return row ? row.GetSysID() : 0; } set { if(row) row.GoToSysID(value); } }
};

public class DriverRow
{
public:
   virtual bool Nil();
   virtual bool Select(MoveOptions move);
   virtual bool Find(Field fld, MoveOptions move, MatchOptions match, typed_object data);
   virtual bool FindMultiple(FieldFindData * findData, MoveOptions move, int numFields);
   virtual bool Synch(DriverRow to);
   virtual bool Add(uint64 id);
   virtual bool Delete();

   virtual bool GetData(Field fld, typed_object &data);
   virtual bool SetData(Field fld, typed_object data);
   virtual uint GetSysID();
   virtual bool GoToSysID(uint id);
   virtual bool Query(char * queryString);
   virtual bool SetQueryParam(int paramID, int value);
   virtual bool SetQueryParam64(int paramID, int64 value);
   virtual bool SetQueryParamText(int paramID, char * value);
   virtual bool SetQueryParamObject(int paramID, void * data, Class type);
   virtual char * GetColumn(int paramID);
};

public class SQLCustomFunction
{
public:
   Array<char> array { minAllocSize = 1024 };
   virtual void Process(char * text);
}

public struct FieldFindData
{
   Field field;
   DataValue value;
};
