# ZenML Batch Inference Template - Implementation Plan

## Executive Summary

**Goal**: Build a standard ZenML batch inference template for the ML Platform team to standardize workflows across Applied ML teams, starting with LTV models.

**Strategy**: MVP template with phased approach - Core → Monitoring → Advanced features

**Key Requirements**:
- Platform flexibility: Support Snowflake SPCS and K-Serve
- Feature engineering: SQL-based (Airflow/Snowflake), future Hopsworks migration path
- Model registry: MLflow (existing implementation)
- Migration: Easy transition from Airflow DAGs to ZenML pipelines

**Timeline**:
- Phase 1 (MVP): 6 weeks
- Phase 2 (Monitoring): 4 weeks
- Phase 3 (Advanced): 6 weeks

---

## Architecture Overview

### Core Design Principles

1. **Configuration-Driven**: YAML configs with environment overrides (Pydantic-based)
2. **Platform Abstraction**: Strategy pattern for Snowflake SPCS / K-Serve flexibility
3. **Reusable Components**: Abstract base classes enforce consistency
4. **SQL-First**: Keep SQL-based feature engineering, migrate orchestration to ZenML
5. **MLflow Native**: Deep integration with existing MLflow infrastructure

### Directory Structure

```
zenml-batch-inference-template/
├── src/
│   ├── pipelines/              # Pipeline definitions
│   │   ├── base_inference_pipeline.py    # Abstract base
│   │   └── batch_inference_pipeline.py   # Concrete implementation
│   ├── steps/                  # ZenML steps by function
│   │   ├── data_loading/       # SQL-based Snowflake loader
│   │   ├── model_loading/      # MLflow model loader
│   │   ├── inference/          # Batch predictor
│   │   ├── output/             # Snowflake output writer
│   │   └── validation/         # Data quality checks
│   ├── config/                 # Pydantic settings
│   ├── platforms/              # Platform adapters (SPCS, K-Serve)
│   └── utils/                  # SQL helpers, currency, logging
├── configs/
│   ├── base.yaml              # Base configuration
│   ├── environments/          # dev/staging/prod overrides
│   └── pipelines/             # Pipeline-specific configs
├── tests/
│   ├── unit/                  # Component tests
│   └── integration/           # E2E pipeline tests
├── scripts/                    # Setup & execution scripts
└── docs/                       # Comprehensive documentation
```

---

## Phase 1: MVP (6 Weeks)

### Week 1-2: Foundation

**Deliverables**:
1. Repository structure with complete directory hierarchy
2. Abstract base classes (`BaseBatchInferencePipeline`, `BaseDataLoader`, `BasePredictor`, `BaseOutputWriter`)
3. Pydantic configuration system with YAML loading
4. Core documentation (README, QUICKSTART)

**Key Components**:

**1. BaseBatchInferencePipeline** - Template method pattern
```python
class BaseBatchInferencePipeline(ABC):
    """
    Abstract base enforcing consistent pipeline structure.
    Implements: load_data → validate → load_model → predict → validate → write_output
    """
    @pipeline
    def run(self, run_config: Optional[Dict] = None):
        # 6-step workflow with hooks for customization
```

**2. PipelineConfig** - Pydantic settings with hierarchical loading
```python
class PipelineConfig(BaseSettings):
    """
    Loads config from: base.yaml → environments/{env}.yaml → env vars
    Sections: data, model, inference, output, validation, monitoring, platform
    """
```

**Reference Files**:
- `/Users/mirajtariq/Desktop/Happening/Github/miraj.private/zenml_snapshot/src/config.py` - Dataclass configuration pattern
- `/Users/mirajtariq/Desktop/Happening/Github/ml.trading.risk-segmentation/src/pipelines/historic_risk_pipeline.py` - Class-based pipeline organization

### Week 3-4: Data & Model Integration

**Deliverables**:
1. `SnowflakeDataLoader` - Execute SQL queries, return DataFrames
2. `MLflowModelLoader` - Load by version/alias from registry
3. `SQLQueryManager` - Organize SQL files, template rendering
4. Basic schema validation

**Key Patterns**:

**1. SQL Passthrough Strategy**
```python
@step
def load_snowflake_features(
    query_name: str,          # e.g., "ltv_features_be"
    connection_params: Dict,
    parameters: Dict          # Query params (dates, tenures)
) -> pd.DataFrame:
    # Execute SQL (from sql_queries/{query_name}.sql)
    # Keep complex aggregations in SQL for performance
    # Return DataFrame for Python processing
```

**2. MLflow Model Loading**
```python
@step
def load_mlflow_model(
    model_name: str,
    model_alias: str = "production"  # or model_version="5"
) -> LoadedModel:
    # Load from MLflow registry
    # Support version-based or alias-based loading
    # Return model + metadata for lineage tracking
```

**Migration Approach**:
- **Keep**: SQL feature engineering queries (migrate to `sql_queries/*.sql`)
- **Migrate**: Orchestration logic (Airflow DAG → ZenML pipeline)
- **Convert**: KubernetesPodOperator → ZenML steps with platform adapters

**Reference Files**:
- `/Users/mirajtariq/Desktop/Happening/Github/data.airflow.dags/dags/tran-ds-ltv-acquisition-be-inference.py` - Belgium LTV DAG (simpler, good starting point)
- `/Users/mirajtariq/Desktop/Happening/Github/miraj.private/MLflow_Technical_Implementation.md` - MLflow integration patterns

### Week 5-6: Inference & Output

**Deliverables**:
1. `BatchPredictor` - Memory-efficient batch inference with metrics
2. `SnowflakeOutputWriter` - INSERT/MERGE with validation
3. `SnowflakeSPCSPlatform` - Basic platform adapter
4. Complete LTV Belgium example pipeline
5. Testing suite (80% coverage)
6. Deployment scripts (`setup_stack.py`, `run_pipeline.py`)

**Key Components**:

**1. Batch Predictor**
```python
@step(experiment_tracker="mlflow_tracker")
def batch_predict(model, data, batch_size=1000):
    # Batch processing (memory-efficient)
    # Error handling per batch
    # Post-processing (capping, rounding)
    # Auto-log metrics to MLflow
```

**2. Snowflake Output Writer**
```python
@step
def write_to_snowflake(
    predictions: pd.DataFrame,
    table_name: str,
    mode: Literal["append", "overwrite", "merge"]
):
    # Support multiple write modes
    # Transaction safety
    # Write validation
```

**3. Platform Abstraction** (Strategy Pattern)
```python
class BasePlatform(ABC):
    def deploy(self, model_uri, config) -> DeploymentResult
    def predict(self, deployment_id, data) -> predictions
    def cleanup(self, deployment_id) -> bool

class SnowflakeSPCSPlatform(BasePlatform):
    # Custom SPCS implementation (no native ZenML support)
    # Create SPCS service, execute inference, cleanup
```

**LTV Belgium Example**:
```python
@pipeline(
    enable_cache=False,
    on_failure=send_incident_alert
)
def ltv_be_inference_pipeline(config: PipelineConfig):
    # 1. Load features (SQL-based from Snowflake)
    features = load_snowflake_features(
        query_name="ltv_features_be",
        parameters={"tenure_months": config.tenure}
    )

    # 2. Load model (from MLflow)
    model = load_mlflow_model(
        model_name="ltv_model_be",
        model_alias="production"
    )

    # 3. Predict
    predictions = batch_predict(model, features, batch_size=1000)

    # 4. Write output
    write_to_snowflake(predictions, config.output_table, mode="append")
```

**Reference Files**:
- `/Users/mirajtariq/Desktop/Happening/Github/ml.trading.risk-segmentation/src/steps/` - Well-structured step implementations
- `/Users/mirajtariq/Desktop/Happening/Github/miraj.private/zenml_snapshot/src/trigger.py` - Execution flow and error handling patterns

### Phase 1 Success Criteria

✅ LTV Belgium pipeline runs end-to-end on Snowflake SPCS
✅ MLflow model loading and experiment tracking functional
✅ SQL-based feature engineering preserved from Airflow
✅ Configuration-driven execution (YAML + env vars)
✅ 80% test coverage (unit + integration)
✅ Complete documentation (README, QUICKSTART, CONFIGURATION, MIGRATION_GUIDE)
✅ Deployment scripts for stack setup and pipeline execution

---

## Phase 2: Monitoring & Observability (4 Weeks)

### Week 7-8: Metrics & Monitoring

**Deliverables**:
1. Enhanced metrics logging step
2. IncidentIO alert integration
3. Performance tracking
4. Grafana dashboard templates

**Components**:
```python
@step(experiment_tracker="mlflow_tracker")
def log_inference_metrics(predictions, model_metadata):
    # Comprehensive metrics (mean, std, percentiles)
    # Prediction statistics
    # Performance benchmarks
    # Log to MLflow + custom monitoring
```

### Week 9-10: Data Quality & Drift

**Deliverables**:
1. `DataQualityValidator` with custom rules
2. Prediction validation gates
3. Basic statistical drift detection
4. Quality reports

**Components**:
```python
@step
def validate_data_quality(data, rules):
    # Schema validation
    # Null checks, range validation
    # Custom business rules
    # Quality gates (fail pipeline if below threshold)
```

---

## Phase 3: Advanced Features (6 Weeks)

### Week 11-13: K-Serve Platform Integration

**Deliverables**:
1. `KServePlatform` adapter
2. Multi-platform configuration
3. Platform comparison guide
4. Enhanced SPCS features

### Week 14-16: Feature Store & CI/CD

**Deliverables**:
1. `HopsworksFeatureStoreLoader` (custom `BaseFeatureStore`)
2. CI/CD pipeline (GitHub Actions)
3. Automated testing in CI
4. Blue-green deployment automation

---

## Key Technical Decisions

### 1. Platform Flexibility Strategy

**Approach**: Strategy pattern with platform adapters

```python
# configs/base.yaml
platform:
  type: "snowflake_spcs"  # or "kserve"
  config:
    compute_pool: "inference_pool"

# Platform factory creates appropriate adapter
platform = PlatformFactory.create(config.platform.type, config.platform.config)
```

**Rationale**:
- Supports both Snowflake SPCS and K-Serve without code changes
- Configuration-driven platform selection
- Easy to add new platforms (extend `BasePlatform`)

### 2. Feature Engineering Approach

**Approach**: SQL-first with Python post-processing

```python
# Heavy lifting in SQL (Snowflake compute)
features = load_snowflake_features(query_name="ltv_features_be")

# Complex logic in Python
features = apply_currency_conversion(features)
features = engineer_time_features(features)
```

**Rationale**:
- Leverages existing SQL queries from Airflow
- Minimal migration effort for Applied ML teams
- SQL optimized for large-scale aggregations
- Python for complex business logic
- Clear migration path to Hopsworks (Phase 3)

### 3. Configuration Hierarchy

**Approach**: Pydantic with YAML + environment variable overrides

```
Priority (high to low):
1. Environment variables (runtime)
2. Runtime config overrides (programmatic)
3. Environment-specific YAML (prod.yaml)
4. Base YAML (base.yaml)
```

**Rationale**:
- Type-safe configuration with Pydantic validation
- Environment-specific overrides for dev/staging/prod
- Secrets via environment variables (security)
- Flexible for different team needs

### 4. MLflow Integration

**Approach**: Native ZenML integration via stack components

```python
# Stack configuration
zenml experiment-tracker register mlflow_tracker --flavor=mlflow
zenml model-registry register mlflow_registry --flavor=mlflow

# Automatic tracking in pipeline
@pipeline(settings={"experiment_tracker": "mlflow_tracker"})
@step(experiment_tracker="mlflow_tracker")
```

**Rationale**:
- Leverages existing MLflow infrastructure
- Automatic experiment tracking
- Model lineage via ZenML + MLflow
- Familiar workflow for teams already using MLflow

---

## Airflow → ZenML Migration Patterns

### External Dependencies (ExternalTaskSensor)

**Airflow**:
```python
wait_for_data = ExternalTaskSensor(
    external_dag_id='feature_engineering_daily'
)
```

**ZenML Options**:
1. **Webhook triggers**: Upstream pipeline triggers downstream via API
2. **Scheduled dependencies**: Ensure upstream runs before downstream (via scheduling)
3. **Manual polling** (temporary): Python step checks upstream completion

**Recommended**: Webhook-based triggers for loose coupling

### Task Dependencies

**Airflow**:
```python
task1 >> task2 >> [task3, task4] >> task5
```

**ZenML**:
```python
@pipeline
def my_pipeline():
    result1 = task1()
    result2 = task2(result1)
    result3 = task3(result2)  # Parallel execution
    result4 = task4(result2)  # automatic with ZenML
    task5(result3, result4)
```

**Automatic**: ZenML infers dependencies from data flow

### Error Handling & Alerting

**Airflow**:
```python
default_args = {
    'retries': 3,
    'on_failure_callback': incidentio_alerts.create_alert
}
```

**ZenML**:
```python
@step(retry=StepRetryConfig(max_retries=3, delay=60, backoff=2))
def my_step():
    pass

@pipeline(on_failure=send_incident_alert)
def my_pipeline():
    pass
```

### Scheduling

**Airflow**:
```python
schedule_interval='0 2 * * *'  # 2 AM daily
```

**ZenML**:
```python
from zenml.config import Schedule

schedule = Schedule(cron_expression="0 2 * * *")
pipeline.run(schedule=schedule)
```

**Note**: Creates Kubernetes CronJob when using K8s orchestrator

---

## Critical Implementation Files

### Files to Reference During Implementation

1. **Configuration Pattern**: `/Users/mirajtariq/Desktop/Happening/Github/miraj.private/zenml_snapshot/src/config.py`
   - Dataclass-based config with validation
   - Environment-based loading
   - Clean composition

2. **MLflow Integration**: `/Users/mirajtariq/Desktop/Happening/Github/miraj.private/MLflow_Technical_Implementation.md`
   - Model loading patterns (226KB of detail)
   - Experiment tracking setup
   - Version/alias management

3. **Pipeline Organization**: `/Users/mirajtariq/Desktop/Happening/Github/ml.trading.risk-segmentation/src/pipelines/historic_risk_pipeline.py`
   - Class-based pipeline structure
   - Training + inference in one class
   - Clean step organization

4. **Step Structure**: `/Users/mirajtariq/Desktop/Happening/Github/ml.trading.risk-segmentation/src/steps/`
   - Well-organized step categories
   - Base classes and abstractions
   - Reusable components

5. **Documentation Style**: `/Users/mirajtariq/Desktop/Happening/Github/miraj.private/zenml_snapshot/docs/QUICKSTART.md`
   - Clear step-by-step guides
   - Troubleshooting sections
   - Example workflows

6. **LTV DAG Logic**: `/Users/mirajtariq/Desktop/Happening/Github/data.airflow.dags/dags/tran-ds-ltv-acquisition-be-inference.py`
   - SQL query patterns
   - Multi-tenure processing
   - Currency conversion logic

---

## Testing Strategy

### Unit Tests (80% coverage target)

```
tests/unit/
├── test_pipelines/         # Pipeline logic
├── test_steps/
│   ├── test_data_loading/  # SQL execution, schema validation
│   ├── test_model_loading/ # MLflow loading, version resolution
│   ├── test_inference/     # Batch prediction, post-processing
│   └── test_output/        # Write operations, validation
├── test_platforms/         # Platform adapters
└── test_config/            # Configuration loading, validation
```

**Key Test Patterns**:
- Mock external dependencies (Snowflake, MLflow, S3)
- Test with realistic fixture data
- Validate error handling paths
- Test configuration edge cases

### Integration Tests

```python
def test_e2e_ltv_pipeline(mock_snowflake, mock_mlflow):
    """Test complete pipeline execution with mocked services"""
    config = PipelineConfig.from_yaml("configs/base.yaml", env="dev")
    pipeline = LTVInferencePipeline(config)
    result = pipeline.run()
    assert result is not None
```

---

## Documentation Deliverables

### Phase 1 Documentation

1. **README.md**: Overview, features, quick start
2. **QUICKSTART.md**: 15-minute getting started guide
3. **CONFIGURATION.md**: Complete config reference with examples
4. **MIGRATION_GUIDE.md**: Airflow → ZenML migration patterns
5. **ARCHITECTURE.md**: Design decisions, patterns, trade-offs
6. **API.md**: Code reference for classes and functions

### Documentation Standards

- **Code examples**: Real, runnable code snippets
- **Troubleshooting**: Common issues and solutions
- **Decision logs**: Document "why" not just "what"
- **Visual aids**: Architecture diagrams, flow charts
- **Version tracking**: Document changes between phases

---

## Success Metrics

### Phase 1 (MVP) Success Criteria

**Functional**:
- ✅ LTV Belgium pipeline runs end-to-end
- ✅ Processes 10,000+ rows efficiently
- ✅ Predictions written to Snowflake correctly
- ✅ MLflow tracking shows all runs with metrics

**Quality**:
- ✅ 80%+ test coverage
- ✅ All unit tests passing
- ✅ Integration tests with mocked services passing
- ✅ No critical security vulnerabilities

**Documentation**:
- ✅ Complete README with examples
- ✅ QUICKSTART guide (15 min to first run)
- ✅ Configuration reference
- ✅ Migration guide for Airflow users

**Adoption**:
- ✅ Applied ML team successfully uses template for 1 model
- ✅ Template saves 50%+ setup time vs. from-scratch
- ✅ Positive feedback from first adopter

---

## Next Steps

### Immediate Actions (Week 1)

1. **Repository Setup**
   - Create template repository with directory structure
   - Initialize with .gitignore, pyproject.toml, README
   - Set up CI/CD skeleton

2. **Environment Preparation**
   - Set up development ZenML stack
   - Configure MLflow connection
   - Prepare test Snowflake environment
   - Create development namespace

3. **Team Alignment**
   - Review plan with ML Platform team
   - Identify first Applied ML team for pilot
   - Schedule weekly sync meetings
   - Set up Slack channel (#ml-platform-templates)

4. **Documentation Setup**
   - Create docs/ structure
   - Set up documentation site (MkDocs)
   - Write initial README

### Development Workflow

**Week 1-2**: Foundation layer (base classes, config system)
**Week 3-4**: Data and model integration
**Week 5-6**: Inference, output, and LTV example
**Week 6**: Testing, documentation, pilot deployment

### Risk Mitigation

**Risk**: Snowflake SPCS custom integration complexity
**Mitigation**: Start with simple SPCS deployment, iterate; have Snowflake native fallback

**Risk**: Migration friction for Applied ML teams
**Mitigation**: Excellent documentation, hands-on migration support, gradual rollout

**Risk**: Platform differences (SPCS vs K-Serve) cause abstraction leaks
**Mitigation**: Keep platform adapter interface minimal, document platform-specific config

---

## Conclusion

This plan provides a comprehensive, phased approach to building a production-ready ZenML batch inference template. The MVP (Phase 1) focuses on core functionality with clear success criteria, while Phases 2-3 add advanced capabilities.

**Key Strengths**:
- Leverages excellent patterns from Risk team's ZenML implementation
- Preserves SQL-based feature engineering from Airflow (minimal migration friction)
- Flexible platform support via Strategy pattern
- MLflow integration leveraging existing infrastructure
- Comprehensive testing and documentation from day one

**Timeline**: 16 weeks total (6 MVP + 4 monitoring + 6 advanced), with MVP delivering value within 6 weeks.

**Success Indicator**: Applied ML teams can migrate from Airflow DAGs to ZenML pipelines in <1 week using this template, with improved observability and flexibility.