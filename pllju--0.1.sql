CREATE FUNCTION pllj_call_handler_u()
  RETURNS language_handler AS 'MODULE_PATHNAME'
  LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION pllj_inline_handler_u(internal)
  RETURNS VOID AS 'MODULE_PATHNAME'
  LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION pllj_validator_u(oid)
  RETURNS VOID AS 'MODULE_PATHNAME'
  LANGUAGE C IMMUTABLE STRICT;

CREATE TRUSTED LANGUAGE pllju
  HANDLER pllj_call_handler_u
  INLINE pllj_inline_handler_u 
  VALIDATOR pllj_validator_u;

