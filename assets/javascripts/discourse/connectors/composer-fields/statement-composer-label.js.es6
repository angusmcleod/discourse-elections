export default {
  setupComponent(attrs) {
    if (attrs.model.isNominationStatement) {
      Ember.run.scheduleOnce('afterRender', () => {
        $('#reply-control .statement-composer-label').detach().appendTo('#reply-control .reply-details');
      });
    }
  }
};
