import ElectionSave from './election-save';
import computed from 'ember-addons/ember-computed-decorators';

export default ElectionSave.extend({
  name: 'poll_time',
  layoutName: 'components/election-save',

  @computed('type', 'enabled', 'after', 'hours', 'nominations', 'time', 'topicUpdated')
  unchanged(type, enabled, after, hours, nominations, time) {
    const originalEnabled = this.get(`topic.election_poll_${type}`);
    const originalAfter = this.get(`topic.election_poll_${type}_after`);
    const originalHours = this.get(`topic.election_poll_${type}_after_hours`);
    const originalNominations = this.get('topic.election_poll_open_after_nominations');
    const originalTime = this.get(`topic.election_poll_${type}_time`);
    return enabled === originalEnabled &&
           after === originalAfter &&
           hours === originalHours &&
           (type === 'open' ? nominations === originalNominations : true) &&
           time === originalTime;
  },

  prepareData() {
    if (this.get(`disabled`)) return false;

    this.setProperties({
      icon: null,
      saving: true
    });

    $('#modal-alert').hide();

    const after = this.get('after');

    let data = {
      topic_id: this.get('topic.id'),
      type: this.get('type'),
      enabled: this.get('enabled'),
      after
    };

    if (after) {
      data['hours'] = this.get('hours');
      data['nominations'] = this.get('nominations');
    } else {
      data['time'] = this.get('time');
    }

    return data;
  },

  resolve(result) {
    const type = this.get('type');
    const enabled = this.get('enabled');
    const after = this.get('after');
    const hours = this.get('hours');
    const nominations = this.get('nominations');
    const time = this.get('time');

    if (result.success) {
      this.set('icon', 'check');
      this.set(`topic.election_poll_${type}`, enabled);
      this.set(`topic.election_poll_${type}_after`, after);
      this.set(`topic.election_poll_${type}_after_hours`, hours);
      this.set(`topic.election_poll_${type}_time`, time);
      if (type === 'open') {
        this.set('topic.election_poll_open_after_nominations', nominations);
      }
      this.toggleProperty('topicUpdated');
    } else if (result.failed) {
      this.setProperties({
        icon: 'times',
        enabled: this.get(`topic.election_poll_${type}`),
        after: this.get(`topic.election_poll_${type}_after`),
        hours: this.get(`topic.election_poll_${type}_after_hours`),
        time: this.get(`topic.election_poll_${type}_time`),
      });
      if (type === 'open') {
        this.set('nominations', this.get('topic.election_poll_open_after_nominations'));
      }
      this.sendAction('error', result.message);
    }

    this.sendAction('saved');
    this.set('saving', false);
  },
});
