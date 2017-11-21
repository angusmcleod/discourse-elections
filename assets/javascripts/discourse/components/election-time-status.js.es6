export default Ember.Component.extend({
  classNames: 'election-status-label',
  nominating: Ember.computed.equal('topic.election_status', 1),
  polling: Ember.computed.equal('topic.election_status', 2)
});
