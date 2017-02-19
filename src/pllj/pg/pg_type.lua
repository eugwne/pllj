local pg_type = {
  bool =    {oid = 16,  tolua = false, topg = false},
  int4 =    {oid = 23,  tolua = false, topg = false},
  text =    {oid = 25,  tolua = false, topg = false},
  unknown = {oid = 705, tolua = false, topg = false},
  int2 =    {oid = 21,  tolua = false, topg = false},
  int8 =    {oid = 20,  tolua = false, topg = false},
}

return {pg_type = pg_type}