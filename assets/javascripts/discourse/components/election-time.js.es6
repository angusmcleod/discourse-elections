import { default as computed, observes, on } from 'ember-addons/ember-computed-decorators';

export default Ember.Component.extend({
  classNames: 'election-time',
  showNominations: Ember.computed.equal('type', 'open'),

  @on('init')
  setup() {
    const after = this.get('after');
    if (!after) this.set('manual', true);
  },

  @observes('after')
  toggleManual() {
    const after = this.get('after');
    if (after) this.set('manual', false);
  },

  @observes('manual')
  toggleAfter() {
    const manual = this.get('manual');
    if (manual) this.set('after', false);
  },

  @computed('type')
  timeId: (type) => `${type}-time-picker`,

  @computed('type')
  dateId: (type) => `${type}-date-picker`,

  @computed('type')
  afterTitle: (type) => `election.poll.${type}_after`,

  @computed('type')
  manualTitle: (type) => `election.poll.${type}_manual`,

  @computed('type')
  criteria(type) {
    const list = I18n.t(`election.poll.${type}_criteria`).split('-');
    return list.filter((c) => c.length > 3);
  },

  actions: {
    setTime(time) {
      this.set('time', time);
    }
  }
});
