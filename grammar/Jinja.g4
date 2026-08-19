/*
 * Jinja.g4 — the normative grammar of dev.cajeta.jinja
 * (cajeta-jinja-spec §2; plan 2.2.1).
 *
 * STATUS: this grammar is the CONTRACT, not a code-generator input.
 * ANTLR4 ships no cajeta target and there is no ANTLR runtime on the
 * cajeta side (every parser written in cajeta is hand-written recursive
 * descent: stdlib `JsonReader`, `ProtobufCursor`, `dev.cajeta.docs`'s
 * Html/Markdown readers — spec 1.5). `Lexer.cajeta` + the Unit 3/4
 * parsers implement this grammar by hand; drift is bounded by the
 * byte-exact fixture corpus generated from real Jinja2 (spec 6.1). If a
 * cajeta ANTLR target ever lands, this file is the input it consumes.
 *
 * Widened from cajeta-llama's ChatTemplate.g4 (the extraction source) to
 * the full spec §2 surface. A construct outside this grammar is an ERROR
 * naming the construct and the line (spec 2.22) — never a silent partial
 * render.
 *
 * WHITESPACE (spec 2.13/2.14) — four independently configurable modes:
 *   - trim_blocks:   a newline IMMEDIATELY after a block or comment tag
 *                    is removed. Default OFF (Jinja's default;
 *                    `transformers` turns it ON).
 *   - lstrip_blocks: horizontal whitespace from line start to a block or
 *                    comment tag is removed. Default OFF.
 *   - Neither applies to `{{ }}` output tags.
 *   - Explicit `{%-`/`-%}`/`{{-`/`-}}`/`{#-`/`-#}` strip ALL adjacent
 *     whitespace including newlines and OVERRIDE the settings; explicit
 *     `{%+` / `+%}` disable the block settings for that one tag.
 */

grammar Jinja;

// ── document ────────────────────────────────────────────────────────────

template    : node* EOF ;

node        : text
            | output
            | comment
            | ifStmt | forStmt | setStmt | withStmt | filterStmt
            | macroStmt | callStmt | rawStmt
            | breakStmt | continueStmt
            | extendsStmt | blockStmt | includeStmt
            ;

text        : TEXT ;
comment     : COMMENT_OPEN .*? COMMENT_CLOSE ;      // consumed by the lexer
output      : VAR_OPEN expr VAR_CLOSE ;

// ── statements (spec 2.2–2.12) ──────────────────────────────────────────

ifStmt      : tagOpen 'if' expr tagClose node*
              (tagOpen 'elif' expr tagClose node*)*
              (tagOpen 'else' tagClose node*)?
              tagOpen 'endif' tagClose ;

forStmt     : tagOpen 'for' nameList 'in' expr ('if' expr)?
              ('recursive')? tagClose node*
              (tagOpen 'else' tagClose node*)?
              tagOpen 'endfor' tagClose ;
nameList    : NAME (',' NAME)* ;

setStmt     : tagOpen 'set' target '=' expr tagClose                // inline
            | tagOpen 'set' target tagClose node*                   // block
              tagOpen 'endset' tagClose ;
target      : NAME ('.' NAME)* ;                    // namespace attr assign

withStmt    : tagOpen 'with' (kwPair (',' kwPair)*)? tagClose node*
              tagOpen 'endwith' tagClose ;
kwPair      : NAME '=' expr ;

filterStmt  : tagOpen 'filter' filterChain tagClose node*
              tagOpen 'endfilter' tagClose ;

macroStmt   : tagOpen 'macro' NAME '(' paramList? ')' tagClose node*
              tagOpen 'endmacro' tagClose ;
paramList   : param (',' param)* ;
param       : NAME ('=' expr)? ;

callStmt    : tagOpen 'call' ('(' paramList? ')')? NAME '(' argList? ')'
              tagClose node*
              tagOpen 'endcall' tagClose ;

rawStmt     : tagOpen 'raw' tagClose ANY*? tagOpen 'endraw' tagClose ;

breakStmt   : tagOpen 'break' tagClose ;            // loopcontrols (2.11)
continueStmt: tagOpen 'continue' tagClose ;

extendsStmt : tagOpen 'extends' expr tagClose ;
blockStmt   : tagOpen 'block' NAME tagClose node*
              tagOpen 'endblock' NAME? tagClose ;
includeStmt : tagOpen 'include' expr ('ignore' 'missing')?
              (('with'|'without') 'context')? tagClose ;

tagOpen     : STMT_OPEN | STMT_OPEN_TRIM | STMT_OPEN_KEEP ;   // {% {%- {%+
tagClose    : STMT_CLOSE | STMT_CLOSE_TRIM | STMT_CLOSE_KEEP ;// %} -%} +%}

// ── expressions, lowest to highest precedence (spec 2.15/2.16) ──────────

// Jinja2's chain, NOT Python's (verified against the 3.1.6 parser):
//   `**` is LEFT-associative (2**3**2 = 64), unary minus binds TIGHTER
//   than `**` (-2**2 = 4), `~` sits BETWEEN +/- and * (1 ~ 2*3 = '16'),
//   comparisons CHAIN (1 < 2 < 3), and `is` tests bind at postfix level
//   (1 < 2 is defined  ==  1 < (2 is defined)).
expr        : condExpr ;
condExpr    : orExpr ('if' orExpr ('else' condExpr)?)? ;   // inline if
orExpr      : andExpr ('or' andExpr)* ;
andExpr     : notExpr ('and' notExpr)* ;
notExpr     : 'not' notExpr | comparison ;
comparison  : additive (compOp additive
              | ('not')? 'in' additive)* ;                 // CHAINED
compOp      : '==' | '!=' | '<' | '<=' | '>' | '>=' ;
additive    : concat (('+'|'-') concat)* ;
concat      : term ('~' term)* ;
term        : power (('*'|'/'|'//'|'%') power)* ;
power       : unary ('**' unary)* ;                        // left-assoc
unary       : ('-'|'+') unary | postfix ;
test        : NAME ('(' argList? ')')? ;                   // spec 2.18
postfix     : primary (('.' NAME)
                      | ('[' slice ']')
                      | ('(' argList? ')')
                      | ('|' filterCall)
                      | ('is' ('not')? test))* ;
slice       : expr | expr? ':' expr? (':' expr?)? ;        // negative ok
filterChain : filterCall ('|' filterCall)* ;
filterCall  : NAME ('(' argList? ')')? ;                   // spec 2.17
argList     : arg (',' arg)* ;
arg         : expr | NAME '=' expr ;
primary     : NUMBER | STRING | 'true' | 'false' | 'none'
            | 'True' | 'False' | 'None'
            | NAME
            | '(' expr (',' expr)* ')'                     // tuple/group
            | '[' argList? ']'                             // list literal
            | '{' (dictPair (',' dictPair)*)? '}' ;        // dict literal
dictPair    : expr ':' expr ;

// ── lexical sketch (the hand lexer is authoritative on bytes) ───────────

NAME        : [a-zA-Z_] [a-zA-Z0-9_]* ;
NUMBER      : [0-9]+ ('.' [0-9]+)? ;
STRING      : '"' (ESC|~["\\])* '"' | '\'' (ESC|~['\\])* '\'' ;
fragment ESC: '\\' . ;
