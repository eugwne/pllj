CREATE FUNCTION pllj_call_handler()
  RETURNS language_handler AS 'MODULE_PATHNAME'
  LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION pllj_inline_handler(internal)
  RETURNS VOID AS 'MODULE_PATHNAME'
  LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION pllj_validator(oid)
  RETURNS VOID AS 'MODULE_PATHNAME'
  LANGUAGE C IMMUTABLE STRICT;

CREATE TRUSTED LANGUAGE pllj
  HANDLER pllj_call_handler
  INLINE pllj_inline_handler 
  VALIDATOR pllj_validator;

