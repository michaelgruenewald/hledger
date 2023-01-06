{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Close (
  closemode
 ,close
)
where

import System.Console.CmdArgs.Explicit as C

import Hledger
import Hledger.Cli.CliOptions
import Hledger.Cli.Commands.Clopen (clopen)
import Data.Maybe (fromMaybe)

defclosingdesc = "retain earnings"
defclosingacct = "equity:retained earnings"

closemode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Close.txt")
  [flagReq  ["close-desc"]   (\s opts -> Right $ setopt "close-desc" s opts) "DESC" ("description for closing transaction (default: "++defclosingdesc++")")
  ,flagReq  ["close-acct"]   (\s opts -> Right $ setopt "close-acct" s opts) "ACCT" ("account to transfer closing balances to (default: "++defclosingacct++")")
  ,flagNone ["explicit","x"] (setboolopt "explicit") "show all amounts explicitly"
  ,flagNone ["interleaved"]  (setboolopt "interleaved") "keep source and destination postings adjacent"
  ,flagNone ["show-costs"]   (setboolopt "show-costs") "keep balances with different costs separate"
  ]
  [generalflagsgroup1]
  (hiddenflags
    -- any old command flags for compatibility, hidden
    -- ++ []
  )
  ([], Just $ argsFlag "[QUERY]")

-- The close command is currently a strict subset of clopen, and we can reuse that code.
close copts@CliOpts{rawopts_=rawopts, reportspec_=rspec@ReportSpec{_rsQuery=q, _rsReportOpts=ropts}} =
  clopen copts{rawopts_=rawopts', reportspec_=rspec'}
  where
    rawopts' =
      setboolopt "close" $ unsetboolopt "open" $ -- show only a closing txn
      setopt "close-desc" (fromMaybe defclosingdesc $ maybestringopt "close-desc" rawopts) $  -- use our default description unless overridden
      setopt "close-acct" (fromMaybe defclosingacct $ maybestringopt "close-acct" rawopts) $  -- use our default closing account unless overridden
      rawopts
    rspec' = rspec{_rsQuery=q'} where
      q' = if null $ querystring_ ropts then Type [Revenue, Expense] else q  -- close RX accounts unless overridden

