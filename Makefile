.PHONY: check
check: ## Run all skill validation checks (frontmatter, YAML, shell syntax, fiz.sh)
	@bash scripts/validate.sh
