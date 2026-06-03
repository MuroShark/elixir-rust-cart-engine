%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/", "web/", "apps/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      color: true,
      parse_timeout: 30_000,
      checks: [
        # Code Consistency Checks
        {Credo.Check.Consistency.ExceptionNames, []},
        {Credo.Check.Consistency.LineEndings, []},
        {Credo.Check.Consistency.ParameterPatternMatching, []},
        {Credo.Check.Consistency.SpaceAroundOperators, []},
        {Credo.Check.Consistency.TabsOrSpaces, []},

        # Architectural and Design Checks
        {Credo.Check.Design.AliasUsage, [priority: :low, if_nested_deeper_than: 2]},
        {Credo.Check.Design.TagTODO, [exit_status: 0]},

        # Readability and Formatting Standards
        {Credo.Check.Readability.AliasOrder, []},
        {Credo.Check.Readability.FunctionNames, []},
        {Credo.Check.Readability.LargeNumbers, [only_greater_than: 99_999]},
        {Credo.Check.Readability.MaxLineLength, [max_length: 120]},
        {Credo.Check.Readability.ModuleDoc, []},
        {Credo.Check.Readability.ParenthesesOnZeroArityDefs, [parens: true]},
        {Credo.Check.Readability.Specs, [exit_status: 0]},

        # Refactoring Opportunities
        {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 9]},
        {Credo.Check.Refactor.DoubleBooleanNegation, []},
        {Credo.Check.Refactor.LongQuoteBlocks, []},
        {Credo.Check.Refactor.MapInto, false},
        {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
        {Credo.Check.Refactor.PipeChainStart, [excluded_functions: ["from"]]},

        # Warnings for Potential Bugs and Unsafe Code
        {Credo.Check.Warning.IExPry, []},
        {Credo.Check.Warning.IoInspect, []},
        {Credo.Check.Warning.LazyLogging, false},
        {Credo.Check.Warning.OperationOnSameValues, []},
        {Credo.Check.Warning.UnusedEnumOperation, []},
        {Credo.Check.Warning.WrongTestFileExtension, []}
      ]
    }
  ]
}
