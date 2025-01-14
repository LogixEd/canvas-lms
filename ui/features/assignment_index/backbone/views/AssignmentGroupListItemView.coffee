#
# Copyright (C) 2013 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

import I18n from 'i18n!AssignmentGroupListItemView'
import $ from 'jquery'
import * as MoveItem from '@canvas/move-item-tray'
import Cache from '../../cache'
import DraggableCollectionView from './DraggableCollectionView.coffee'
import AssignmentListItemView from './AssignmentListItemView.coffee'
import CreateAssignmentView from './CreateAssignmentView.coffee'
import CreateGroupView from './CreateGroupView.coffee'
import DeleteGroupView from './DeleteGroupView.coffee'
import preventDefault from 'prevent-default'
import template from '../../jst/AssignmentGroupListItem.handlebars'
import AssignmentKeyBindingsMixin from '../mixins/AssignmentKeyBindingsMixin'
import {shimGetterShorthand} from '@canvas/util/legacyCoffeesScriptHelpers'
import React from 'react'
import ReactDOM from 'react-dom'
import ContentTypeExternalToolTray from '@canvas/trays/react/ContentTypeExternalToolTray'
import {ltiState} from '@canvas/lti/jquery/post_message/handleLtiPostMessage'


export default class AssignmentGroupListItemView extends DraggableCollectionView
  @mixin AssignmentKeyBindingsMixin
  @optionProperty 'course'
  @optionProperty 'userIsAdmin'

  tagName: "li"
  className: "item-group-condensed"
  itemView: AssignmentListItemView
  template: template

  @child 'createAssignmentView', '[data-view=createAssignment]'
  @child 'editGroupView', '[data-view=editAssignmentGroup]'
  @child 'deleteGroupView', '[data-view=deleteAssignmentGroup]'

  els: Object.assign({}, @::els, {
    '.add_assignment': '$addAssignmentButton'
    '.delete_group': '$deleteGroupButton'
    '.edit_group': '$editGroupButton'
    '.move_group': '$moveGroupButton'
  })

  events:
    'click .element_toggler': 'toggleArrow'
    'keyclick .element_toggler': 'toggleArrowWithKeyboard'
    'click .tooltip_link': preventDefault ->
    'keydown .assignment_group': 'handleKeys'
    'click .move_contents':  'onMoveContents'
    'click .move_group':  'onMoveGroup'
    'click .ag-header-controls .menu_tool_link': 'openExternalTool'

  messages: shimGetterShorthand {},
    toggleMessage: -> I18n.t('toggle_message', "toggle assignment visibility")

  # call remove on children so that they can clean up old dialogs.
  # this should eventually happen at a higher level (eg for all views), but
  # we need to make sure that all children view are also children dom
  # elements first.
  render: =>
    @createAssignmentView.remove() if @createAssignmentView
    @editGroupView.remove() if @editGroupView
    @deleteGroupView.remove() if @deleteGroupView
    super(@canManage())

    # reset the model's view property; it got overwritten by child views
    @model.view = this if @model

  afterRender: ->
    # need to hide child views and set trigger manually
    if @createAssignmentView
      @createAssignmentView.hide()
      @createAssignmentView.setTrigger @$addAssignmentButton

    if @editGroupView
      @editGroupView.hide()
      @editGroupView.setTrigger @$editGroupButton

    if @deleteGroupView
      @deleteGroupView.hide()
      @deleteGroupView.setTrigger @$deleteGroupButton

    if @model.hasRules()
      @createRulesToolTip()

  createItemView: (model) ->
    options =
      userIsAdmin: @userIsAdmin
    new @itemView $.extend {}, {model}, options

  createRulesToolTip: =>
    link = @$el.find('.tooltip_link')
    link.tooltip
      position:
        my: 'center top'
        at: 'center bottom+10'
        collision: 'fit fit'
      tooltipClass: 'center top vertical'
      content: ->
        $(link.data('tooltipSelector')).html()

  initialize: ->
    @initializeCollection()
    super
    @assignment_group_menu_tools = ENV.assignment_group_menu_tools || []
    @initializeChildViews()

    # we need the following line in order to access this view later
    @model.groupView = @
    @initCache()

  initializeCollection: ->
    @model.get('assignments').each (assign) ->
      assign.doNotParse() if assign.multipleDueDates()

    @collection = @model.get('assignments')
    @collection.on 'add',  => @expand(false)

  initializeChildViews: ->
    @editGroupView = false
    @createAssignmentView = false
    @deleteGroupView = false

    if @canAdd()
      @editGroupView = new CreateGroupView
        assignmentGroup: @model
        userIsAdmin: @userIsAdmin
      @createAssignmentView = new CreateAssignmentView
        assignmentGroup: @model
    if @canDelete()
      @deleteGroupView = new DeleteGroupView
        model: @model

  initCache: ->
    $.extend true, @, Cache
    @cache.use('localStorage')
    key = @cacheKey()
    if !@cache.get(key)?
      @cache.set(key, true)

  initSort: ->
    opts = if ENV?.FEATURES?.responsive_misc then {handle: '.draggable-handle'} else {}
    super(opts)
    @$list.on('sortactivate', @startSort)
      .on('sortdeactivate', @endSort)

  startSort: (e, ui) =>
    # When there is 1 assignment in this group and you drag an assignment
    # from another group, don't insert the noItemView
    if @collection.length == 1 && $(ui.placeholder).data("group") == @model.id
      @insertNoItemView()

  endSort: (e, ui) =>
    if @collection.length == 0 && @$list.children().length < 1
      @insertNoItemView()
    else if @$list.children().length > 1
      @removeNoItemView()

  toJSON: ->
    data = @model.toJSON()
    showWeight = @course?.get('apply_assignment_group_weights') and data.group_weight?
    canMove = @model.collection.length > 1

    attributes = Object.assign(data, {
      course_home: ENV.COURSE_HOME
      canMove: canMove
      canDelete: @canDelete()
      showRules: @model.hasRules()
      rulesText: I18n.t('rules_text', "Rule", { count: @model.countRules() })
      displayableRules: @displayableRules()
      showWeight: showWeight
      groupWeight: data.group_weight
      toggleMessage: @messages.toggleMessage
      hasFrozenAssignments: @model.hasFrozenAssignments? and @model.hasFrozenAssignments()
      hasIntegrationData: @model.hasIntegrationData? and @model.hasIntegrationData()
      postToSISName: ENV.SIS_NAME
      assignmentGroupMenuPlacements: @assignment_group_menu_tools
      ENV: ENV
    })

  displayableRules: ->
    rules = @model.rules() or {}
    results = []

    if rules.drop_lowest? and rules.drop_lowest > 0
      results.push(I18n.t('drop_lowest_rule', {
        'one': 'Drop the lowest score',
        'other': 'Drop the lowest %{count} scores'
      }, {
        'count': rules.drop_lowest
      }))

    if rules.drop_highest? and rules.drop_highest > 0
      results.push(I18n.t('drop_highest_rule', {
        'one': 'Drop the highest score',
        'other': 'Drop the highest %{count} scores'
      }, {
        'count': rules.drop_highest
      }))

    if rules.never_drop? and rules.never_drop.length > 0
      rules.never_drop.forEach (never_drop_assignment_id) =>
        assign = @model.get('assignments').findWhere(id: never_drop_assignment_id)

        # TODO: students won't see never drop rules for unpublished
        # assignments because we don't know if the assignment is missing
        # because it is unpublished or because it has been moved or deleted.
        # Once those cases are handled better, we can add a default here.
        if name = assign?.get('name')
          results.push(I18n.t('never_drop_rule', 'Never drop %{assignment_name}', {
            'assignment_name': name
          }))

    results

  search: (regex, gradingPeriod) ->
    @resetBorders()
    assignmentCount = @collection.reduce( (count, as) =>
      count++ if as.search(regex, gradingPeriod)
      count
    , 0)

    atleastone = assignmentCount > 0
    if atleastone
      @show()
      @expand(false)
      @borderFix()
    else
      @hide()
    assignmentCount

  endSearch: ->
    @resetBorders()

    @show()
    @collapseIfNeeded()
    @resetNoToggleCache()
    @collection.each (as) =>
      as.endSearch()

  resetBorders: ->
    @$('.first_visible').removeClass('first_visible')
    @$('.last_visible').removeClass('last_visible')

  borderFix: ->
    @$('.search_show').first().addClass("first_visible")
    @$('.search_show').last().addClass("last_visible")

  shouldBeExpanded: ->
    @cache.get(@cacheKey())

  collapseIfNeeded: ->
    @collapse(false) unless @shouldBeExpanded()

  expand: (toggleCache=true) =>
    @_setNoToggleCache() unless toggleCache
    @toggleCollapse() unless @currentlyExpanded()

  collapse: (toggleCache=true) =>
    @_setNoToggleCache() unless toggleCache
    @toggleCollapse() if @currentlyExpanded()

  toggleCollapse: (toggleCache=true) ->
    @_setNoToggleCache() unless toggleCache
    @$el.find('.element_toggler').click()

  _setNoToggleCache: ->
    @$el.find('.element_toggler').data("noToggleCache", true)

  currentlyExpanded: ->
    # the 2 states of the element toggler are true and "false"
    if @$el.find('.element_toggler').attr("aria-expanded") == "false"
      false
    else
      true

  cacheKey: ->
    ["course", @course.get('id'), "user", @currentUserId(), "ag", @model.get('id'), "expanded"]

  toggleArrow: (ev) =>
    arrow = $(ev.currentTarget).children('i')
    arrow.toggleClass('icon-mini-arrow-down').toggleClass('icon-mini-arrow-right')
    @toggleCache() unless $(ev.currentTarget).data("noToggleCache")
    #reset noToggleCache because it is a one-time-use-only flag
    @resetNoToggleCache(ev.currentTarget)

  toggleArrowWithKeyboard: (ev) =>
    $(ev.target).click()
    false

  resetNoToggleCache: (selector=null) ->
    if selector?
      obj = $(selector)
    else
      obj = @$el.find('.element_toggler')
    obj.data("noToggleCache", false)

  toggleCache: ->
    key = @cacheKey()
    expanded = !@cache.get(key)
    @cache.set(key, expanded)

  onMoveGroup: () =>
    @moveTrayProps =
      title: I18n.t('Move Group')
      items: [
        id: @model.get('id')
        title: @model.get('name')
      ]
      moveOptions:
        siblings: MoveItem.backbone.collectionToItems(@model.collection)
      onMoveSuccess: (res) =>
        MoveItem.backbone.reorderInCollection(res.data.order, @model)
      focusOnExit: =>
        document.querySelector("#assignment_group_#{@model.id} a[id*=manage_link]")
      formatSaveUrl: => ENV.URLS.sort_url

    MoveItem.renderTray(@moveTrayProps, document.getElementById('not_right_side'))

  onMoveContents: () =>
    groupItems = MoveItem.backbone.collectionToItems(@model, (col) => col.get('assignments'))
    groupItems[0].groupId = @model.get('id')
    @moveTrayProps =
      title: I18n.t('Move Contents Into')
      items: groupItems
      moveOptions:
        groupsLabel: I18n.t('Assignment Group')
        groups: MoveItem.backbone.collectionToGroups(@model.collection, (col) => col.get('assignments'))
        excludeCurrent: true
      onMoveSuccess: (res) =>
        keys =
          model: 'assignments'
          parent: 'assignment_group_id'
        MoveItem.backbone.reorderAllItemsIntoNewCollection(res.data.order, res.groupId, @model, keys)
      focusOnExit: =>
        document.querySelector("#assignment_group_#{@model.id} a[id*=manage_link]")
      formatSaveUrl: ({ groupId }) ->
        "#{ENV.URLS.assignment_sort_base_url}/#{groupId}/reorder"

    MoveItem.renderTray(@moveTrayProps, document.getElementById('not_right_side'))

  hasMasterCourseRestrictedAssignments: ->
    @model.get('assignments').any (m) ->
      m.isRestrictedByMasterCourse()

  canDelete: ->
    ENV.PERMISSIONS.manage_assignments_delete &&
      (@userIsAdmin or @model.canDelete()) &&
      !@hasMasterCourseRestrictedAssignments()

  canAdd: ->
    ENV.PERMISSIONS.manage_assignments_add

  canManage: ->
    ENV.PERMISSIONS.manage

  currentUserId: ->
    ENV.current_user_id

  isVisible: =>
    $("#assignment_group_#{@model.id}").is(":visible")

  goToNextItem: =>
    if @hasVisibleAssignments()
      @focusOnAssignment(@firstAssignment())
    else if @nextGroup()?
      @focusOnGroup(@nextGroup())
    else
      @focusOnFirstGroup()

  goToPrevItem: =>
    if @previousGroup()?
      if @previousGroup().view.hasVisibleAssignments()
        @focusOnAssignment(@previousGroup().view.lastAssignment())
      else
        @focusOnGroup(@previousGroup())
    else
      if @lastVisibleGroup().view.hasVisibleAssignments()
        @focusOnAssignment(@lastVisibleGroup().view.lastAssignment())
      else
        @focusOnGroup(@lastVisibleGroup())

  addItem: =>
    $(".add_assignment", "#assignment_group_#{@model.id}").click()

  editItem: =>
    $(".edit_group[data-focus-returns-to='ag_#{@model.id}_manage_link']").click()

  deleteItem: =>
    $(".delete_group[data-focus-returns-to='ag_#{@model.id}_manage_link']").click()

  visibleAssignments: =>
    @collection.filter (assign) ->
      assign.attributes.hidden != true

  hasVisibleAssignments: =>
    @currentlyExpanded() and @visibleAssignments().length

  firstAssignment: =>
    @visibleAssignments()[0]

  lastAssignment: =>
    @visibleAssignments()[@visibleAssignments().length - 1]

  visibleGroupsInCollection: =>
    @model.collection.filter (group) ->
      group.view.isVisible()

  nextGroup: =>
    place_in_groups_collection = @visibleGroupsInCollection().indexOf(@model)
    @visibleGroupsInCollection()[place_in_groups_collection + 1]

  previousGroup: =>
    place_in_groups_collection = @visibleGroupsInCollection().indexOf(@model)
    @visibleGroupsInCollection()[place_in_groups_collection - 1]

  focusOnGroup: (group) =>
    $("#assignment_group_#{group.attributes.id}").attr("tabindex",-1).focus()

  focusOnAssignment: (assignment) =>
    $("#assignment_#{assignment.id}").attr("tabindex",-1).focus()

  focusOnFirstGroup: =>
    $(".assignment_group").filter(":visible").first().attr("tabindex",-1).focus()

  lastVisibleGroup: =>
    last_group_index = @visibleGroupsInCollection().length - 1
    @visibleGroupsInCollection()[last_group_index]

  openExternalTool: (ev) =>
    if (ev != null)
      ev.preventDefault()

    tool = @assignment_group_menu_tools.find((t) => t.id == ev.target.dataset.toolId)
    @setExternalToolTray(tool, @$el.find('.al-trigger')[0])

  reloadPage: =>
    window.location.reload()

  setExternalToolTray: (tool, returnFocusTo) =>
    handleDismiss = () =>
      @setExternalToolTray(null)
      returnFocusTo.focus()
      if ltiState?.tray?.refreshOnClose
        @reloadPage()

    groupData =
      id: @model.get('id')
      name: @model.get('name')
    props =
      tool: tool
      placement: "assignment_group_menu"
      acceptedResourceTypes: ['assignment']
      targetResourceType: 'assignment'
      allowItemSelection: false
      selectableItems: [groupData]
      onDismiss: handleDismiss
      open: tool != null

    component = React.createElement(ContentTypeExternalToolTray, props)
    ReactDOM.render(component, $('#external-tool-mount-point')[0])
