{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Clopen (
  clopenmode
 ,clopen
)
where

import Control.Monad (when)
import Data.Function (on)
import Data.List (groupBy)
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Time.Calendar (addDays)
import Lens.Micro ((^.))
import System.Console.CmdArgs.Explicit as C

import Hledger
import Hledger.Cli.CliOptions

defclosingdesc = "closing balances"
defopeningdesc = "opening balances"
defclosingacct = "equity:opening/closing balances"
defopeningacct = defclosingacct

clopenmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Clopen.txt")
  [flagNone ["close"]        (setboolopt "close") "show just closing transaction"
  ,flagNone ["open"]         (setboolopt "open") "show just opening transaction"
  ,flagReq  ["close-desc"]   (\s opts -> Right $ setopt "close-desc" s opts) "DESC" ("description for closing transaction (default: "++defclosingdesc++")")
  ,flagReq  ["open-desc"]    (\s opts -> Right $ setopt "open-desc"  s opts) "DESC" ("description for opening transaction (default: "++defopeningdesc++")")
  ,flagReq  ["close-acct"]   (\s opts -> Right $ setopt "close-acct" s opts) "ACCT" ("account to transfer closing balances to (default: "++defclosingacct++")")
  ,flagReq  ["open-acct"]    (\s opts -> Right $ setopt "open-acct"  s opts) "ACCT" ("account to transfer opening balances from (default: "++defopeningacct++")")
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

-- Debugger, beware: clopen is incredibly devious; simple rules combine to make a horrid maze.
-- Tests are in hledger/test/clopen.test.
-- This code is also used by the close command.
clopen copts@CliOpts{rawopts_=rawopts, reportspec_=rspec'} j = do
  let
    -- show opening entry, closing entry, or (default) both ?
    (opening, closing) =
      case (boolopt "open" rawopts, boolopt "close" rawopts) of
        (False, False) -> (True, True)
        (o, c)         -> (o, c)

    -- descriptions to use for the closing/opening transactions
    closingdesc = maybe (T.pack defclosingdesc) T.pack $ maybestringopt "close-desc" rawopts
    openingdesc = maybe (T.pack defopeningdesc) T.pack $ maybestringopt "open-desc" rawopts

    -- accounts to close to and open from
    -- if only one is specified, it is used for both
    (closingacct, openingacct) =
      let (mc, mo) =
            (T.pack <$> maybestringopt "close-acct" rawopts, T.pack <$> maybestringopt "open-acct" rawopts)
      in case (mc, mo) of
        (Just c, Just o)   -> (c, o)
        (Just c, Nothing)  -> (c, c)
        (Nothing, Just o)  -> (o, o)
        (Nothing, Nothing) -> (T.pack defclosingacct, T.pack defopeningacct)

    ropts = (_rsReportOpts rspec'){balanceaccum_=Historical, accountlistmode_=ALFlat}
    rspec = setDefaultConversionOp NoConversionOp rspec'{_rsReportOpts=ropts}

    -- dates of the closing and opening transactions
    -- Clopen.md:
    -- "The default closing date is yesterday, or the journal's end date, whichever is later.
    -- You can change this by specifying a [report end date](#report-start--end-date),
    -- where "last day of the report period" will be the closing date.
    -- (Only the end date matters; a report start date will be ignored.)
    -- The opening date is always the day after the closing date."
    q = _rsQuery rspec
    yesterday = addDays (-1) $ _rsDay rspec
    yesterdayorjournalend = case journalLastDay False j of
      Just journalend -> max yesterday journalend
      Nothing         -> yesterday
    mreportlastday = addDays (-1) <$> queryEndDate False q
    closingdate = fromMaybe yesterdayorjournalend  mreportlastday
    openingdate = addDays 1 closingdate

    -- should we show the amount(s) on the equity posting(s) ?
    explicit = boolopt "explicit" rawopts || copts ^. infer_costs

    -- the balances to close
    (acctbals',_) = balanceReport rspec j
    acctbals = map (\(a,_,_,b) -> (a, if show_costs_ ropts then b else mixedAmountStripPrices b)) acctbals'
    totalamt = maSum $ map snd acctbals

    -- since balance assertion amounts are required to be exact, the
    -- amounts in opening/closing transactions should be too (#941, #1137)
    precise = amountSetFullPrecision

    -- interleave equity postings next to the corresponding closing posting, or put them all at the end ?
    interleaved = boolopt "interleaved" rawopts

    -- the closing transaction
    closingtxn = nulltransaction{tdate=closingdate, tdescription=closingdesc, tpostings=closingps}
    closingps =
      concat [
        posting{paccount          = a
               ,pamount           = mixedAmount . precise $ negate b
               -- after each commodity's last posting, assert 0 balance (#1035)
               -- balance assertion amounts are unpriced (#824)
               ,pbalanceassertion =
                   if islast
                   then Just nullassertion{baamount=precise b{aquantity=0, aprice=Nothing}}
                   else Nothing
               }

        -- maybe an interleaved posting transferring this balance to equity
        : [posting{paccount=closingacct, pamount=mixedAmount $ precise b} | interleaved]

        | -- get the balances for each commodity and transaction price
          (a,mb) <- acctbals
        , let bs0 = amounts mb
          -- mark the last balance in each commodity with True
        , let bs2 = concat [reverse $ zip (reverse bs1) (True : repeat False)
                           | bs1 <- groupBy ((==) `on` acommodity) bs0]
        , (b, islast) <- bs2
        ]

      -- or a final multicommodity posting transferring all balances to equity
      -- (print will show this as multiple single-commodity postings)
      ++ [posting{paccount=closingacct, pamount=if explicit then mixedAmountSetFullPrecision totalamt else missingmixedamt} | not interleaved]

    -- the opening transaction
    openingtxn = nulltransaction{tdate=openingdate, tdescription=openingdesc, tpostings=openingps}
    openingps =
      concat [
        posting{paccount          = a
               ,pamount           = mixedAmount $ precise b
               ,pbalanceassertion =
                   case mcommoditysum of
                     Just s  -> Just nullassertion{baamount=precise s{aprice=Nothing}}
                     Nothing -> Nothing
               }
        : [posting{paccount=openingacct, pamount=mixedAmount . precise $ negate b} | interleaved]

        | (a,mb) <- acctbals
        , let bs0 = amounts mb
          -- mark the last balance in each commodity with the unpriced sum in that commodity (for a balance assertion)
        , let bs2 = concat [reverse $ zip (reverse bs1) (Just commoditysum : repeat Nothing)
                           | bs1 <- groupBy ((==) `on` acommodity) bs0
                           , let commoditysum = (sum bs1)]
        , (b, mcommoditysum) <- bs2
        ]
      ++ [posting{paccount=openingacct, pamount=if explicit then mixedAmountSetFullPrecision (maNegate totalamt) else missingmixedamt} | not interleaved]

  -- print them
  when closing . T.putStr $ showTransaction closingtxn
  when opening . T.putStr $ showTransaction openingtxn
