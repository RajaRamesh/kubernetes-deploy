# frozen_string_literal: true
require 'test_helper'

class DaemonSetTest < KubernetesDeploy::TestCase
  def setup
    super
    KubernetesDeploy::Kubectl.any_instance.expects(:run).never
  end

  def test_deploy_not_successful_when_updated_available_does_not_match
    ds_template = build_ds_template
    ds = build_synced_ds(template: ds_template)
    refute_predicate ds, :deploy_succeeded?
  end

  def test_deploy_succeeded_not_fooled_by_stale_status
    status = {
      "observedGeneration": 1,
      "numberReady": 2,
      "desiredNumberScheduled": 2,
      "updatedNumberScheduled": 2,
    }
    ds_template = build_ds_template(status: status)
    ds = build_synced_ds(template: ds_template)
    refute_predicate ds, :deploy_succeeded?
  end

  def test_deploy_failed_ensures_controller_has_observed_deploy
    ds_template = build_ds_template(status: { "observedGeneration": 1 })
    ds = build_synced_ds(template: ds_template)
    ds.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate ds, :deploy_failed?
  end

  def test_deploy_passes_when_updated_available_does_match
    status = {
      "currentNumberScheduled": 3,
      "desiredNumberScheduled": 2,
      "numberReady": 2,
      "updatedNumberScheduled": 2,
      "observedGeneration": 2,
    }

    ds_template = build_ds_template(status: status)
    ds = build_synced_ds(template: ds_template)
    assert_predicate ds, :deploy_succeeded?
  end

  private

  def build_ds_template(status: {})
    base_ds_maifest = YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), 'daemon_set.yml'))).first
    base_ds_maifest.deep_merge("status" => status)
  end

  def build_synced_ds(template:)
    ds = KubernetesDeploy::DaemonSet.new(namespace: "test", context: "nope", logger: logger, definition: template)
    sync_mediator = build_sync_mediator
    sync_mediator.kubectl.expects(:run).with("get", "DaemonSet", "ds-app", "-a", "--output=json").returns(
      [template.to_json, "", SystemExit.new(0)]
    )

    sync_mediator.kubectl.expects(:run).with("get", "Pod", "-a", "--output=json", anything).returns(
      ['{ "items": [] }', "", SystemExit.new(0)]
    )

    ds.sync(sync_mediator)
    ds
  end

  def build_sync_mediator
    KubernetesDeploy::SyncMediator.new(namespace: 'test', context: 'minikube', logger: logger)
  end
end
