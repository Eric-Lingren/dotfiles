# artifact-grounding-judge eval: inputs for review

46 cases. 29 expect `pass`, 17 expect `rejected`. Each case runs the judge in a sandbox holding only that base's frozen fixture files.

Non-exact cases show only the evidence entries that differ from their base record. Every other field matches the `exact_` case for that base.

| id | kind | base conf | expected verdict | expected conf | write |
|---|---|---|---|---|---|
| exact_b000 | exact | confirmed | pass | confirmed | yes |
| exact_b004 | exact | confirmed | pass | confirmed | yes |
| exact_b011 | exact | confirmed | pass | confirmed | yes |
| exact_b015 | exact | confirmed | pass | confirmed | yes |
| exact_b019 | exact | confirmed | pass | confirmed | yes |
| exact_b020 | exact | confirmed | pass | confirmed | yes |
| exact_b030 | exact | candidate | pass | candidate | yes |
| exact_b052 | exact | candidate | pass | candidate | yes |
| exact_b076 | exact | candidate | pass | candidate | yes |
| exact_b087 | exact | candidate | pass | candidate | yes |
| exact_b116 | exact | candidate | pass | candidate | yes |
| exact_b131 | exact | candidate | pass | candidate | yes |
| fabricated_b004 | fabricated | confirmed | rejected | confirmed | no |
| fabricated_b011 | fabricated | confirmed | rejected | confirmed | no |
| fabricated_b015 | fabricated | confirmed | rejected | confirmed | no |
| fabricated_b019 | fabricated | confirmed | rejected | confirmed | no |
| fabricated_b030 | fabricated | candidate | rejected | candidate | no |
| fabricated_b052 | fabricated | candidate | rejected | candidate | no |
| fabricated_b087 | fabricated | candidate | rejected | candidate | no |
| fabricated_b131 | fabricated | candidate | rejected | candidate | no |
| wrong_file_b000 | wrong_file | confirmed | rejected | confirmed | no |
| wrong_file_b011 | wrong_file | confirmed | rejected | confirmed | no |
| wrong_file_b076 | wrong_file | candidate | rejected | candidate | no |
| wrong_file_b116 | wrong_file | candidate | rejected | candidate | no |
| paraphrase_b000 | paraphrase | confirmed | pass | candidate | yes |
| paraphrase_b000_2 | paraphrase | confirmed | pass | candidate | yes |
| paraphrase_b011 | paraphrase | confirmed | pass | candidate | yes |
| paraphrase_b015 | paraphrase | confirmed | pass | candidate | yes |
| paraphrase_b020 | paraphrase | confirmed | pass | candidate | yes |
| paraphrase_b030 | paraphrase | candidate | pass | candidate | yes |
| whitespace_b011 | whitespace | confirmed | pass | confirmed | yes |
| whitespace_b019 | whitespace | confirmed | pass | confirmed | yes |
| whitespace_b087 | whitespace | candidate | pass | candidate | yes |
| whitespace_b131 | whitespace | candidate | pass | candidate | yes |
| missing_file_b004 | missing_file | confirmed | pass | candidate | yes |
| missing_file_b019 | missing_file | confirmed | pass | candidate | yes |
| missing_file_b052 | missing_file | candidate | pass | candidate | yes |
| missing_file_b116 | missing_file | candidate | pass | candidate | yes |
| missing_plus_fab_b019 | missing_plus_fab | confirmed | rejected | confirmed | no |
| missing_plus_fab_b052 | missing_plus_fab | candidate | rejected | candidate | no |
| absence_true_b015 | absence_true | confirmed | pass | confirmed | yes |
| absence_true_b000 | absence_true | confirmed | pass | confirmed | yes |
| absence_true_b020 | absence_true | confirmed | pass | confirmed | yes |
| absence_false_b131 | absence_false | candidate | rejected | candidate | no |
| absence_false_b030 | absence_false | candidate | rejected | candidate | no |
| absence_false_b087 | absence_false | candidate | rejected | candidate | no |

## exact_b000

Expected: **pass** / confirmed. Write: yes.

Problem: A new physical file `learning-schema-v2.json` was created instead of bumping `learning-schema.json` in place. The JSON Schema already carries a `schema_version` const field (v1="1", v2="2") that fully tracks the version internally. A version-suffixed filename only earns its keep when old v1 data mus

- ref `docs/seeds/20260605-1358-retro-attribution-learning.json`

```
Unify three learning forks (existing skill-learning, future agent-learning, this retroactive-attribution) into ONE system: one v2 superset schema, one physical append-only log. The existing per-skill-file layout is replaced and the live skill-learning system is rewired into the unified log. Done now while there is zero data, because convergence is near-free today and a migration project later.
```

- ref `docs/seeds/20260605-1358-retro-attribution-learning.json`

```
Unification requires migrating the live skill-learning system (24 tail blocks, capture-learning agent, log-learning.py, learning-schema.json, learnings/ dir). Cheap now with zero data, expensive once data and the agent-learning fork accrue.
```

- ref `docs/tasks/20260605-1501-retro-attribution-learning.json`

```
Create the v2 superset learning schema at `claude-code-shared/contracts/learning-schema-v2.json`.
```


## exact_b004

Expected: **pass** / confirmed. Write: yes.

Problem: Five TS2739/TS2322 compile errors in two Vitest test files reached CircleCI type-check and broke CI. The errors were introduced when NavCoordContextValue gained gridMeta and setPendingExitFocus fields on branch key-1698, but the test-file mocks were not updated. The errors went undetected locally be

- ref `client/biome-local.sh`

```
yarn biome
```

- ref `client/package.json`

```
"test": "vitest run",
```

- ref `claude-code-shared/skills/tdd/SKILL.md`

```
## Checklist Per Cycle
```


## exact_b011

Expected: **pass** / confirmed. Write: yes.

Problem: FYEChangeBanner's BannerExportButton called useMetricsUrlParams() with no arguments, so it silently defaulted cadence/date-range derivation to FYE_AT_MIN_YEAR and currency to USD, instead of passing the company's real fiscalYearEnd and preferredCurrency the way Filters.tsx and useMetricsTableData.ts

- ref `client/src/pages/portfolio-company/hooks/useMetricsUrlParams.ts`

```
Accepts fiscalYearEnd and reportingCurrency to compute sensible date and currency defaults when no URL params
 * are present. Pass these from useCompanyDetails() and useGetCurrencyForCompany().
```

- ref `client/src/modules/portfolio-company/metrics/components/FYEChangeBanner.tsx`

```
const { cadence, startDate, endDate, currency } = useMetricsUrlParams()
```

- ref `client/src/modules/portfolio-company/metrics/Filters.tsx`

```
} = useMetricsUrlParams({
    fiscalYearEnd: fiscalYearEndDate,
    reportingCurrency: preferredCurrency,
  })
```


## exact_b015

Expected: **pass** / confirmed. Write: yes.

Problem: InvestmentDetailsBetaContainer was created in T-0102 (KEY-1879 cutover) without an InvestmentsProvider wrapper. The sibling InvestmentDetailsContainer wraps in both CurrencyContext.Provider and InvestmentsProvider. InvestmentDetailsOverview calls useSelectedInvestmentDetails and destructures setModa

- ref `docs/tasks/20260722-0955-key-1935-portco-cutover-scaffolding.json`

```
"CurrencyContext.Provider (preferredCurrency) and InvestmentsProvider (empty value) both present in wrapper tree"
```

- ref `docs/tasks/20260722-0955-key-1935-portco-cutover-scaffolding.json`

```
"status": "blocked"
```


## exact_b019

Expected: **pass** / confirmed. Write: yes.

Problem: _dedupe_column_names only tracks counts per original name and never checks whether a generated suffix already exists in the input list. Inputs like ["Revenue", "Revenue 2", "Revenue"] still produce two "Revenue 2" values, so df.rename raises DuplicateError.

- ref `app/firm_exports/dashboard.py`

```
    seen: dict[str, int] = {}
    result: list[str] = []
    for name in names:
        if name in seen:
            seen[name] += 1
            result.append(f"{name} {seen[name]}")
        else:
            seen[name] = 1
            result.append(name)
    return result
```

- ref `app/firm_exports/tests/test_portfolio_dashboard.py`

```
        (
            ["Revenue", "As Of Date", "Revenue", "As Of Date", "Revenue"],
            ["Revenue", "As Of Date", "Revenue 2", "As Of Date 2", "Revenue 3"],
        ),
```


## exact_b020

Expected: **pass** / confirmed. Write: yes.

Problem: TDD cycle ran for T-0076 (investigator-github.md): 18 tests written first; RED phase produced 8 structural failures (agent file missing) and 10 schema-test passes; GREEN phase produced 18/18 passes after the agent file was created.

- ref `docs/tasks/.logs/20260814-1236-investigation-egress-architecture/T-0076.md`

```
RED run: 8 FAILED (agent file missing), 10 PASSED (schema tests)
```

- ref `docs/tasks/.logs/20260814-1236-investigation-egress-architecture/T-0076.md`

```
GREEN run: 18/18 PASSED in 0.08s
```


## exact_b030

Expected: **pass** / candidate. Write: yes.

Problem: The ORDERING_OPTIONS array in DataChecksInboxPanel.tsx maps 'Age: Newest first' to DataCheckItemsOrdering['-age'] and 'Age: Oldest first' to DataCheckItemsOrdering.age, inverting the intended sort labels. The backend (core.py:71) documents that ascending age (no dash) = smallest age = newest flagged

- ref `app/data_checks/core.py`

```
# Ascending age is the smallest age first, i.e. the newest `flagged_at`
        # first, so the sort direction is inverted relative to the timestamp.
```

- ref `client/src/modules/data-checks/DataChecksInboxPanel.tsx`

```
{ value: DataCheckItemsOrdering['-age'], label: 'Age: Newest first' },
  { value: DataCheckItemsOrdering.age, label: 'Age: Oldest first' },
```


## exact_b052

Expected: **pass** / candidate. Write: yes.

Problem: PR added MULTI_SELECT inputUnit support to EditableTable.tsx and EditableMetrics.tsx but left both mutation paths unguarded: EditableMetrics.tsx L127 applies value.replace(/,/g, '') without checking for MULTI_SELECT, corrupting JSON array strings like '["optionA","optionB"]' into '["optionA""optionB

- ref `clients/web/src/pages/portfolio-company/EditableMetrics.tsx`

```
const formattedValue =
      metricCategory === Category.CUSTOM && inputUnit === ValueType.STRING ? value : value.replace(/,/g, '')
```

- ref `clients/web/src/pages/metrics-repository/components/DatumCategorySections/hooks/useMetricsTableCrud/index.tsx`

```
body: { value: value.replace(/,/g, '') || null, currency }
```


## exact_b076

Expected: **pass** / candidate. Write: yes.

Problem: T-0003 fixed hasFormErrors to use hasDeepErrors, but did not account for MetricSectionTable calling setFieldValue on data load, which triggers Formik validateOnChange with no registered validator, resetting errors to {}. Editing any other metric after a date validation error clears the error object 

- ref `clients/web/src/pages/reports/components/MetricSectionTable/index.tsx`

```
setFieldValue(`metrics[${granularity}]`, flatData)
```

- ref `clients/web/src/pages/reports/index.tsx`

```
<Formik<ReportFormValues>
      initialValues={
        {
          documents,
          metrics: {}, // Metrics is set via setFieldValue within the onSuccess for each table fetch
          reportKPIData: reportKPIResults,
        } satisfies ReportFormValues
      }
      onSubmit={() => {}}
    >
```


## exact_b087

Expected: **pass** / candidate. Write: yes.

Problem: useCreateOrUpdateMetric accepted a fieldName parameter that no production caller ever passes (DateMetricCell.tsx:36, DefaultMetricCell.tsx:100, SelectMetricCell.tsx:29), making the entire Formik sync block dead code. Additionally, the block reads .updatedAt (camelCase, index.ts:209) but writes .upda

- ref `clients/web/src/pages/reports/hooks/useCreateOrUpdateMetric/index.ts`

```
const prevUpdatedAt = fieldName ? getIn(formikContext?.values, `${fieldName}.updatedAt`) : undefined
```

- ref `clients/web/src/pages/reports/hooks/useCreateOrUpdateMetric/index.ts`

```
formikContext?.setFieldValue(`${fieldName}.updated_at`, new Date().toISOString())
```

- ref `clients/web/src/pages/reports/components/Cells/DateMetricCell.tsx`

```
const { createOrUpdateOfMetric } = useCreateOrUpdateMetric({
    autosubmitReport,
    setIsAutoSubmittedModalOpen,
  })
```

- ref `clients/web/src/pages/reports/hooks/useCreateOrUpdateMetric/index.jsdom.test.ts`

```
if (path === 'metric.updatedAt') return previousUpdatedAt
```


## exact_b116

Expected: **pass** / candidate. Write: yes.

Problem: AddCustomMetricModal.tsx line 143 changed defaultValues.metricType from `category?.data_type ?? null` to `toDisplayType(category.data_type, category.is_multiple)`. This change runs in edit mode as well as create mode. When the flag ENABLE_NEW_IR_FIELD_TYPES is off, typeOptions excludes MULTI_SELECT,

- ref `clients/web/src/pages/information-requests/components/MetricLibrary/AddCustomMetricModal.tsx`

```
metricType: category ? toDisplayType(category.data_type, category.is_multiple) : null,
```

- ref `clients/web/src/pages/information-requests/components/MetricLibrary/AddCustomMetricModal.tsx`

```
const typeOptions = useMemo(() => {
    const options = [...selectDataTypeOptions]
    if (flags?.[FLAGS.ENABLE_NEW_IR_FIELD_TYPES]) {
      options.push({ value: ValueType.MULTI_SELECT, label: <MetricTypeIconWithText type={ValueType.MULTI_SELECT} /> })
    }
    return options
  }, [flags])
```

- ref `clients/web/src/pages/information-requests/components/MetricLibrary/AddCustomMetricModal.test.tsx`

```
const category: MetricCategory = {
  name: 'Existing metric',
  description: 'description',
  formula: '',
  is_global: true,
  is_cumulative: false,
  is_point_in_time: true,
  id: 3425,
  data_type: ValueType.MONEY,
  is_archived: false,
  choices: [],
  is_aggregated: false,
}
```


## exact_b131

Expected: **pass** / candidate. Write: yes.

Problem: parseDate in date-utils.ts has no year-range guard. date-fns parse() with format token yyyy is width-lenient (matches 1–4 digits), so '12/25/25' via MM/dd/yyyy yields year 0025. A manual refactor commit (54173d1479) moved date-utils.ts to a new location and rewrote it, dropping MIN_DATE, MAX_DATE, a

- ref `clients/web/src/components/DateInput/date-utils.ts`

```
export const ALLOWED_DATE_FORMATS = [
  'MM/dd/yyyy', // 12/25/2025
  'M/d/yyyy', // 1/1/2025
  'yyyy-MM-dd', // 2025-12-25
  'MM-dd-yyyy', // 12-25-2025
  'MMMM d, yyyy', // December 25, 2025
] as const
```

- ref `clients/web/src/components/legacy/components/DatePicker.tsx`

```
const ALLOWED_DATE_FORMATS = ['MM-dd-yy', 'MM/dd/yy', 'yyyy-MM-dd', 'MM/dd/yyyy', 'MM-dd-yyyy']
```


## fabricated_b004

Expected: **rejected** / confirmed. Write: no.

- ref `client/package.json`  (changed)

```
"test": "jest --run",
```


## fabricated_b011

Expected: **rejected** / confirmed. Write: no.

- ref `client/src/modules/portfolio-company/metrics/components/FYEChangeBanner.tsx`  (changed)

```
const { cadence, startDate, endDate } = useMetricsUrlParams({ fiscalYearEnd })
```


## fabricated_b015

Expected: **rejected** / confirmed. Write: no.

- ref `docs/tasks/20260722-0955-key-1935-portco-cutover-scaffolding.json`  (changed)

```
"status": "cancelled"
```


## fabricated_b019

Expected: **rejected** / confirmed. Write: no.

- ref `app/firm_exports/tests/test_portfolio_dashboard.py`  (changed)

```
        (
            ["Revenue", "As Of Date", "Revenue", "As Of Date", "Revenue"],
            ["Revenue", "As Of Date", "Revenue (2)", "As Of Date 2", "Revenue 3"],
        ),
```


## fabricated_b030

Expected: **rejected** / candidate. Write: no.

- ref `app/data_checks/core.py`  (changed)

```
# Ascending age is the smallest age first, i.e. the oldest `flagged_at`
        # first, so the sort direction is inverted relative to the timestamp.
```


## fabricated_b052

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/pages/metrics-repository/components/DatumCategorySections/hooks/useMetricsTableCrud/index.tsx`  (changed)

```
body: { value: value.replace(/,/g, '') ?? null, currency }
```


## fabricated_b087

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/pages/reports/hooks/useCreateOrUpdateMetric/index.ts`  (changed)

```
formikContext?.setFieldValue(`${fieldName}.updatedAt`, new Date().toISOString())
```


## fabricated_b131

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/components/legacy/components/DatePicker.tsx`  (changed)

```
const ALLOWED_DATE_FORMATS = ['MM/dd/yy', 'yyyy-MM-dd', 'MM/dd/yyyy', 'MM-dd-yyyy']
```


## wrong_file_b000

Expected: **rejected** / confirmed. Write: no.

- ref `docs/seeds/20260605-1358-retro-attribution-learning.json`  (changed)

```
Create the v2 superset learning schema at `claude-code-shared/contracts/learning-schema-v2.json`.
```


## wrong_file_b011

Expected: **rejected** / confirmed. Write: no.

- ref `client/src/modules/portfolio-company/metrics/components/FYEChangeBanner.tsx`  (changed)

```
} = useMetricsUrlParams({
    fiscalYearEnd: fiscalYearEndDate,
    reportingCurrency: preferredCurrency,
  })
```


## wrong_file_b076

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/pages/reports/index.tsx`  (changed)

```
setFieldValue(`metrics[${granularity}]`, flatData)
```


## wrong_file_b116

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/pages/information-requests/components/MetricLibrary/AddCustomMetricModal.tsx`  (changed)

```
const category: MetricCategory = {
  name: 'Existing metric',
  description: 'description',
  formula: '',
  is_global: true,
  is_cumulative: false,
  is_point_in_time: true,
  id: 3425,
  data_type: ValueType.MONEY,
  is_archived: false,
  choices: [],
  is_aggregated: false,
}
```


## paraphrase_b000

Expected: **pass** / candidate. Write: yes.

- ref `docs/seeds/20260605-1358-retro-attribution-learning.json`  (changed)

```
Merge the three learning forks (the existing skill-learning, the planned agent-learning, and retroactive attribution) into a single system with one v2 superset schema and one append-only log. The per-skill-file layout goes away and live skill-learning is rewired to the unified log. Doing it now costs almost nothing since there is no data yet; later it would be a migration project.
```


## paraphrase_b000_2

Expected: **pass** / candidate. Write: yes.

- ref `docs/seeds/20260605-1358-retro-attribution-learning.json`  (changed)

```
Unifying means the live skill-learning system has to be migrated: 24 tail blocks, the capture-learning agent, log-learning.py, learning-schema.json and the learnings/ directory. It is cheap while there is no data and gets expensive once data and the agent-learning fork build up.
```


## paraphrase_b011

Expected: **pass** / candidate. Write: yes.

- ref `client/src/pages/portfolio-company/hooks/useMetricsUrlParams.ts`  (changed)

```
Takes fiscalYearEnd and reportingCurrency so it can derive reasonable date and currency defaults when the URL has no params. Callers should pass values from useCompanyDetails() and useGetCurrencyForCompany().
```


## paraphrase_b015

Expected: **pass** / candidate. Write: yes.

- ref `docs/tasks/20260722-0955-key-1935-portco-cutover-scaffolding.json`  (changed)

```
"Both CurrencyContext.Provider (with preferredCurrency) and an InvestmentsProvider with an empty value are present in the wrapper tree"
```


## paraphrase_b020

Expected: **pass** / candidate. Write: yes.

- ref `docs/tasks/.logs/20260814-1236-investigation-egress-architecture/T-0076.md`  (changed)

```
Green run: all 18 tests passed in 0.08 seconds
```


## paraphrase_b030

Expected: **pass** / candidate. Write: yes.

- ref `app/data_checks/core.py`  (changed)

```
# Sorting by ascending age puts the newest flagged_at first, which means the sort order is the reverse of the timestamp order.
```


## whitespace_b011

Expected: **pass** / confirmed. Write: yes.

- ref `client/src/pages/portfolio-company/hooks/useMetricsUrlParams.ts`  (changed)

```
Accepts fiscalYearEnd and reportingCurrency to compute sensible date and currency defaults when no URL params * are present. Pass these from useCompanyDetails() and useGetCurrencyForCompany().
```


## whitespace_b019

Expected: **pass** / confirmed. Write: yes.

- ref `app/firm_exports/dashboard.py`  (changed)

```
seen: dict[str, int] = {} result: list[str] = [] for name in names: if name in seen: seen[name] += 1 result.append(f"{name} {seen[name]}") else: seen[name] = 1 result.append(name) return result
```


## whitespace_b087

Expected: **pass** / candidate. Write: yes.

- ref `clients/web/src/pages/reports/components/Cells/DateMetricCell.tsx`  (changed)

```
const { createOrUpdateOfMetric } = useCreateOrUpdateMetric({ autosubmitReport, setIsAutoSubmittedModalOpen, })
```


## whitespace_b131

Expected: **pass** / candidate. Write: yes.

- ref `clients/web/src/components/DateInput/date-utils.ts`  (changed)

```
export const ALLOWED_DATE_FORMATS = [ 'MM/dd/yyyy', // 12/25/2025 'M/d/yyyy', // 1/1/2025 'yyyy-MM-dd', // 2025-12-25 'MM-dd-yyyy', // 12-25-2025 'MMMM d, yyyy', // December 25, 2025 ] as const
```


## missing_file_b004

Expected: **pass** / candidate. Write: yes.

- ref `client/biome-check.sh`  (changed)

```
yarn biome
```


## missing_file_b019

Expected: **pass** / candidate. Write: yes.

- ref `app/firm_exports/dashboard_v2.py`  (changed)

```
    seen: dict[str, int] = {}
    result: list[str] = []
    for name in names:
        if name in seen:
            seen[name] += 1
            result.append(f"{name} {seen[name]}")
        else:
            seen[name] = 1
            result.append(name)
    return result
```


## missing_file_b052

Expected: **pass** / candidate. Write: yes.

- ref `clients/web/src/pages/portfolio-company/EditableMetricsV2.tsx`  (changed)

```
const formattedValue =
      metricCategory === Category.CUSTOM && inputUnit === ValueType.STRING ? value : value.replace(/,/g, '')
```


## missing_file_b116

Expected: **pass** / candidate. Write: yes.

- ref `clients/web/src/pages/information-requests/components/MetricLibrary/AddCustomMetricModal.spec.tsx`  (changed)

```
const category: MetricCategory = {
  name: 'Existing metric',
  description: 'description',
  formula: '',
  is_global: true,
  is_cumulative: false,
  is_point_in_time: true,
  id: 3425,
  data_type: ValueType.MONEY,
  is_archived: false,
  choices: [],
  is_aggregated: false,
}
```


## missing_plus_fab_b019

Expected: **rejected** / confirmed. Write: no.

- ref `app/firm_exports/dashboard_v2.py`  (changed)

```
    seen: dict[str, int] = {}
    result: list[str] = []
    for name in names:
        if name in seen:
            seen[name] += 1
            result.append(f"{name} {seen[name]}")
        else:
            seen[name] = 1
            result.append(name)
    return result
```

- ref `app/firm_exports/tests/test_portfolio_dashboard.py`  (changed)

```
        (
            ["Revenue", "As Of Date", "Revenue", "As Of Date", "Revenue"],
            ["Revenue", "As Of Date", "Revenue (2)", "As Of Date 2", "Revenue 3"],
        ),
```


## missing_plus_fab_b052

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/pages/portfolio-company/EditableMetricsV2.tsx`  (changed)

```
const formattedValue =
      metricCategory === Category.CUSTOM && inputUnit === ValueType.STRING ? value : value.replace(/,/g, '')
```

- ref `clients/web/src/pages/metrics-repository/components/DatumCategorySections/hooks/useMetricsTableCrud/index.tsx`  (changed)

```
body: { value: value.replace(/,/g, '') ?? null, currency }
```


## absence_true_b015

Expected: **pass** / confirmed. Write: yes.

- ref `docs/tasks/20260722-0955-key-1935-portco-cutover-scaffolding.json`  (changed)

```
The identifier "useInvestmentsQuery" does not appear anywhere in this file.
```


## absence_true_b000

Expected: **pass** / confirmed. Write: yes.

- ref `docs/tasks/20260605-1501-retro-attribution-learning.json`  (changed)

```
No task in this file mentions "migrate-learnings.py".
```


## absence_true_b020

Expected: **pass** / confirmed. Write: yes.

- ref `docs/tasks/.logs/20260814-1236-investigation-egress-architecture/T-0076.md`  (changed)

```
The word "flaky" does not appear in this log.
```


## absence_false_b131

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/components/DateInput/date-utils.ts`  (changed)

```
The format 'yyyy-MM-dd' is missing from this file.
```


## absence_false_b030

Expected: **rejected** / candidate. Write: no.

- ref `client/src/modules/data-checks/DataChecksInboxPanel.tsx`  (changed)

```
No "Oldest first" sort option appears in this file.
```


## absence_false_b087

Expected: **rejected** / candidate. Write: no.

- ref `clients/web/src/pages/reports/hooks/useCreateOrUpdateMetric/index.jsdom.test.ts`  (changed)

```
The test never stubs the 'metric.updatedAt' path.
```

