import computed from 'ember-addons/ember-computed-decorators';

export default Ember.Component.extend({
  classNames: 'election-status-label',
  nominating: Ember.computed.equal('topic.election_status', 1),
  polling: Ember.computed.equal('topic.election_status', 2),

  @computed('topic.election_poll_open_after_hours')
  pollOpenTime(hours) {
    if (hours > 0) {
      return ` ${I18n.t('dates.medium.x_hours', { count: hours })}`;
    } else {
      return '';
    }
  }
});
