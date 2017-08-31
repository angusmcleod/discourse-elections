import { createWidget } from 'discourse/widgets/widget';
import { getOwner } from 'discourse-common/lib/get-owner';
import showModal from 'discourse/lib/show-modal';
import { ElectionStatuses } from '../lib/election';
import { ajax } from 'discourse/lib/ajax';
import { h } from 'virtual-dom';

export default createWidget('election-controls', {
  tagName: 'div.election-controls',
  buildKey: () => `election-controls`,

  defaultState(attrs) {
    this.appEvents.on('header:update-topic', () => {
      this.scheduleRerender();
    });

    return {
      startingElection: false
    }
  },

  toggleNomination() {
    const topic = this.attrs.topic;
    const categoryId = topic.category_id;
    const topicId = topic.id;
    const position = topic.election_position;
    const isNominee = topic.election_is_nominee;

    showModal('confirm-nomination', {
      model: {
        isNominee,
        categoryId,
        topicId,
        position
      }
    });
  },

  makeStatement() {
    const controller = getOwner(this).lookup('controller:composer');
    const topic = this.attrs.topic;

    controller.open({
      action: 'reply',
      draftKey: 'reply',
      draftSequence: 0,
      topic
    });

    controller.set('model.electionNominationStatement', true);
  },

  manage() {
    showModal('manage-election', {
      model: {
        topic: this.attrs.topic
      }
    });
  },

  startElection() {
    const topicId = this.attrs.topic.id;

    ajax('/election/start', {type: 'PUT', data: { topic_id: topicId}}).then((result) => {
      if (result.failed) {
        bootbox.alert(result.message);
      } else {
        this.attrs.topic.set('election_status', ElectionStatuses['poll']);
      }

      this.state.startingElection = false;
      this.scheduleRerender();
    })

    this.state.startingElection = true;
    this.scheduleRerender();
  },

  html(attrs, state) {
    const topic = attrs.topic;
    const user = this.currentUser;
    const isNominee = topic.election_is_nominee;
    let contents = [];

    if (topic.election_status === ElectionStatuses['nomination'] && topic.election_self_nomination_allowed === "true") {
      contents.push(this.attach('button', {
        action: `toggleNomination`,
        label: `election.nomination.${isNominee ? 'remove.label' : 'add.label'}`,
        className: 'btn btn-primary'
      }))
    }

    if (isNominee && !topic.election_made_statement) {
      contents.push(this.attach('button', {
        action: 'makeStatement',
        label: `election.nomination.statement.add`,
        className: 'btn btn-primary'
      }))
    }

    if (user.is_elections_admin) {
      contents.push(this.attach('button', {
        action: 'manage',
        label: 'election.manage.label',
        className: 'btn btn-primary'
      }))
    }

    if (user.is_elections_admin && topic.election_status === ElectionStatuses['nomination']) {
      contents.push(this.attach('button', {
        action: 'startElection',
        label: 'election.start',
        className: 'btn btn-primary'
      }))

      if (state.startingElection) {
        contents.push(h('div.spinner-container', h('div.spinner.small')))
      }
    }

    return contents;
  }
})
